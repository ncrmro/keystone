//! Repository management operations for ks.

use anyhow::{Context, Result};
use home::home_dir;
use serde::Deserialize;
use std::path::{Path, PathBuf};
use tokio::fs;

use crate::config::KeystoneRepo;

const DEFAULT_INSTALLED_REPO_NAME: &str = "keystone-config";

/// Detected repository layout.
///
/// Legacy repos have a top-level `hosts.nix` attribute set.
/// Generated `mkSystemFlake` repos use `flake.nix` + `hosts/` directory
/// and expose hosts via `nixosConfigurations` flake outputs.
#[derive(Debug, Clone)]
pub enum RepoLayout {
    /// Legacy layout: top-level `hosts.nix` file.
    HostsNix(PathBuf),
    /// mkSystemFlake layout: `flake.nix` + `hosts/` directory.
    FlakeHosts(PathBuf),
}

/// Detect the repository layout at the given root.
pub fn detect_layout(repo_root: &Path) -> Option<RepoLayout> {
    let hosts_nix = repo_root.join("hosts.nix");
    if hosts_nix.is_file() {
        return Some(RepoLayout::HostsNix(hosts_nix));
    }
    if repo_root.join("flake.nix").is_file() && repo_root.join("hosts").is_dir() {
        return Some(RepoLayout::FlakeHosts(repo_root.to_path_buf()));
    }
    None
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostInfo {
    pub hostname: String,
    #[serde(default)]
    pub ssh_target: Option<String>,
    #[serde(default)]
    pub fallback_ip: Option<String>,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub host_public_key: Option<String>,
    #[serde(default)]
    pub build_on_remote: bool,
}

/// Return the base repos directory (~/.keystone/repos/).
fn repos_dir() -> Result<PathBuf> {
    let home = home_dir().context("Failed to get home directory")?;
    Ok(home.join(".keystone").join("repos"))
}

fn looks_like_keystone_repo(path: &Path) -> bool {
    path.join("docs").join("ks.md").is_file()
        && path.join("flake.nix").is_file()
        && path.join("packages").join("ks").exists()
}

fn normalize_repo_root(path: &Path) -> Option<PathBuf> {
    detect_layout(path)?;
    std::fs::canonicalize(path)
        .ok()
        .or_else(|| Some(path.to_path_buf()))
}

fn current_git_root() -> Option<PathBuf> {
    let output = std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    Some(PathBuf::from(
        String::from_utf8_lossy(&output.stdout).trim(),
    ))
}

fn nonempty_env_path(var: &str) -> Option<PathBuf> {
    std::env::var_os(var)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn repo_resolution_error(source: &str, path: &Path) -> anyhow::Error {
    anyhow::anyhow!(
        "Configured {} points to {}, but that path is not a Keystone config repo.\n\
         Expected hosts.nix (legacy) or flake.nix + hosts/ (mkSystemFlake).",
        source,
        path.display()
    )
}

fn canonical_installed_repo_path_for(home: &Path, owner: &str) -> PathBuf {
    home.join(".keystone")
        .join("repos")
        .join(owner)
        .join(DEFAULT_INSTALLED_REPO_NAME)
}

fn current_repo_owner(home: &Path) -> Option<String> {
    std::env::var("USER")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .or_else(|| {
            home.file_name()
                .map(|name| name.to_string_lossy().to_string())
                .filter(|value| !value.is_empty())
        })
}

fn canonical_installed_repo_path(home: &Path) -> Option<PathBuf> {
    current_repo_owner(home).map(|owner| canonical_installed_repo_path_for(home, &owner))
}

/// Walk up to `max_depth` levels looking for a directory with a recognized layout.
///
/// Checks for `hosts.nix` (legacy) first, then `flake.nix` + `hosts/` (mkSystemFlake).
fn find_config_repo_recursive(dir: &Path, max_depth: usize) -> Option<PathBuf> {
    if max_depth == 0 {
        return None;
    }

    let entries = std::fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() && path.file_name().and_then(|name| name.to_str()) == Some("hosts.nix") {
            let parent = path.parent()?.to_path_buf();
            return std::fs::canonicalize(&parent).ok().or(Some(parent));
        }
        if !path.is_dir() {
            continue;
        }
        if detect_layout(&path).is_some() {
            return std::fs::canonicalize(&path).ok().or(Some(path));
        }
        if let Some(found) = find_config_repo_recursive(&path, max_depth - 1) {
            return Some(found);
        }
    }

    None
}

fn find_repo_with_context(
    home: &Path,
    nixos_config_dir: Option<&Path>,
    git_root: Option<&Path>,
    keystone_system_flake: Option<&Path>,
) -> Result<PathBuf> {
    if let Some(path) = nixos_config_dir {
        return normalize_repo_root(path)
            .ok_or_else(|| repo_resolution_error("NIXOS_CONFIG_DIR", path));
    }

    if let Some(root) = git_root.and_then(normalize_repo_root) {
        return Ok(root);
    }

    if let Some(path) = keystone_system_flake {
        if let Some(repo) = normalize_repo_root(path) {
            return Ok(repo);
        }
        return Err(repo_resolution_error("KEYSTONE_SYSTEM_FLAKE", path));
    }

    if let Some(repo) =
        canonical_installed_repo_path(home).and_then(|path| normalize_repo_root(&path))
    {
        return Ok(repo);
    }

    let repos = home.join(".keystone").join("repos");
    if repos.is_dir() {
        if let Some(found) = find_config_repo_recursive(&repos, 3) {
            return Ok(found);
        }
    }

    let fallback = home.join("nixos-config");
    if let Some(repo) = normalize_repo_root(&fallback) {
        return Ok(repo);
    }

    anyhow::bail!(
        "Cannot find a Keystone config repo.\n\
         Looked for, in order:\n\
           - NIXOS_CONFIG_DIR\n\
           - current git repo root\n\
           - KEYSTONE_SYSTEM_FLAKE\n\
           - ~/.keystone/repos/<owner>/{DEFAULT_INSTALLED_REPO_NAME}\n\
           - ~/.keystone/repos/**\n\
           - ~/nixos-config",
    )
}

/// Locate the active Keystone config repository.
pub fn find_repo() -> Result<PathBuf> {
    let home = home_dir().context("No home directory")?;
    find_repo_with_context(
        &home,
        nonempty_env_path("NIXOS_CONFIG_DIR").as_deref(),
        current_git_root().as_deref(),
        nonempty_env_path("KEYSTONE_SYSTEM_FLAKE").as_deref(),
    )
}

/// Discover a local checkout for a repo registry key (`owner/repo`).
pub fn find_local_repo(repo_root: &Path, key: &str) -> Option<PathBuf> {
    let name = key.rsplit('/').next().unwrap_or(key);
    let home = home_dir()?;

    let candidates = [
        home.join(".keystone").join("repos").join(key),
        repo_root.join(".repos").join(name),
        repo_root.join(".submodules").join(name),
        repo_root.join(name),
    ];

    candidates.into_iter().find(|candidate| candidate.is_dir())
}

/// Locate a local Keystone checkout from the current shell context.
pub fn resolve_keystone_repo() -> Result<PathBuf> {
    if let Ok(output) = std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if output.status.success() {
            let root = PathBuf::from(String::from_utf8_lossy(&output.stdout).trim());
            if looks_like_keystone_repo(&root) {
                return Ok(root);
            }
        }
    }

    if let Some(home) = home_dir() {
        let configured_repo = home.join(".keystone").join("repos").join("ncrmro/keystone");
        if looks_like_keystone_repo(&configured_repo) {
            return Ok(configured_repo);
        }
    }

    if let Ok(repo_root) = find_repo() {
        if let Some(keystone_repo) = find_local_repo(&repo_root, "ncrmro/keystone") {
            if looks_like_keystone_repo(&keystone_repo) {
                return Ok(keystone_repo);
            }
        }

        let sibling = repo_root.join("keystone");
        if looks_like_keystone_repo(&sibling) {
            return Ok(sibling);
        }
    }

    anyhow::bail!(
        "could not find a local keystone checkout with a docs/ directory.\n\
         Expected one of:\n\
           - current repo root\n\
           - ~/.keystone/repos/ncrmro/keystone\n\
           - <nixos-config>/.repos/keystone"
    )
}

/// List all host keys from the repository.
pub async fn list_hosts(repo_root: &Path) -> Result<Vec<String>> {
    let layout = detect_layout(repo_root)
        .context("Cannot detect repo layout. Expected hosts.nix or flake.nix + hosts/.")?;

    let output = match &layout {
        RepoLayout::HostsNix(hosts_nix) => tokio::process::Command::new("nix")
            .args(["eval", "-f"])
            .arg(hosts_nix)
            .args(["--json", "--apply", "builtins.attrNames"])
            .output()
            .await
            .context("Failed to list hosts from hosts.nix")?,
        RepoLayout::FlakeHosts(root) => {
            let mut cmd = tokio::process::Command::new("nix");
            cmd.arg("eval")
                .arg(format!("{}#nixosConfigurations", root.display()))
                .args(["--apply", "builtins.attrNames", "--json"]);
            for arg in local_override_args(repo_root).await? {
                cmd.arg(arg);
            }
            cmd.output()
                .await
                .context("Failed to list hosts from flake nixosConfigurations")?
        }
    };

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Failed to enumerate hosts: {}", stderr.trim());
    }

    serde_json::from_slice(&output.stdout).context("Failed to parse host list from nix eval output")
}

/// Resolve the current hostname to a host key.
///
/// When `host` is `None`, looks up the current machine's hostname.
/// Supports both `hosts.nix` (legacy) and `mkSystemFlake` (flake) layouts.
pub async fn resolve_host(repo_root: &Path, host: Option<&str>) -> Result<String> {
    let layout = detect_layout(repo_root)
        .context("Cannot detect repo layout. Expected hosts.nix or flake.nix + hosts/.")?;

    if let Some(host) = host {
        // Validate that the host exists.
        let hosts = list_hosts(repo_root).await?;
        if hosts.iter().any(|h| h == host) {
            return Ok(host.to_string());
        }
        let known = hosts.join(", ");
        anyhow::bail!("Unknown host '{}'. Known hosts: {}", host, known);
    }

    let current_hostname = hostname::get()
        .context("Failed to get hostname")?
        .to_string_lossy()
        .to_string();

    match &layout {
        RepoLayout::HostsNix(hosts_nix) => {
            let expr = format!(
                "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"{}\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m",
                current_hostname,
            );

            let output = tokio::process::Command::new("nix")
                .args(["eval", "-f"])
                .arg(hosts_nix)
                .arg("--raw")
                .arg("--apply")
                .arg(&expr)
                .output()
                .await
                .context("Failed to resolve host from hostname")?;

            let host_key = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if host_key.is_empty() {
                anyhow::bail!(
                    "No hosts.nix entry with hostname '{}'. Specify HOST explicitly.",
                    current_hostname
                );
            }
            Ok(host_key)
        }
        RepoLayout::FlakeHosts(root) => {
            // In the flake layout, try matching the hostname against
            // nixosConfigurations.<key>.config.networking.hostName, or fall
            // back to matching the attribute name directly.
            let hosts = list_hosts(repo_root).await?;

            // First try: attribute name matches hostname directly.
            if hosts.iter().any(|h| h == &current_hostname) {
                return Ok(current_hostname);
            }

            // Second try: evaluate networking.hostName for each host.
            for host_key in &hosts {
                let mut cmd = tokio::process::Command::new("nix");
                cmd.arg("eval")
                    .arg(format!(
                        "{}#nixosConfigurations.{}.config.networking.hostName",
                        root.display(),
                        host_key,
                    ))
                    .arg("--raw");
                for arg in local_override_args(repo_root).await? {
                    cmd.arg(arg);
                }
                if let Ok(output) = cmd.output().await {
                    if output.status.success() {
                        let hn = String::from_utf8_lossy(&output.stdout).trim().to_string();
                        if hn == current_hostname {
                            return Ok(host_key.clone());
                        }
                    }
                }
            }

            anyhow::bail!(
                "No host entry with hostname '{}'. Specify HOST explicitly.",
                current_hostname
            );
        }
    }
}

/// Resolve the current host from the running machine hostname.
pub async fn resolve_current_host(repo_root: &Path) -> Result<Option<String>> {
    match resolve_host(repo_root, None).await {
        Ok(host) => Ok(Some(host)),
        Err(_) => Ok(None),
    }
}

/// Parse a comma-separated host list into individual host names.
pub async fn resolve_hosts(repo_root: &Path, hosts_arg: Option<&str>) -> Result<Vec<String>> {
    match hosts_arg {
        Some(arg) if !arg.is_empty() => {
            let mut result = Vec::new();
            for host in arg.split(',') {
                let host = host.trim();
                if !host.is_empty() {
                    result.push(resolve_host(repo_root, Some(host)).await?);
                }
            }
            Ok(result)
        }
        _ => Ok(vec![resolve_host(repo_root, None).await?]),
    }
}

/// Read `repos.nix` and return its JSON value.
/// Returns an empty object if the file does not exist.
pub async fn get_repos_registry(repo_root: &Path) -> Result<serde_json::Value> {
    let repos_nix = repo_root.join("repos.nix");
    if !repos_nix.is_file() {
        return Ok(serde_json::json!({}));
    }

    let output = tokio::process::Command::new("nix")
        .args(["eval", "-f"])
        .arg(&repos_nix)
        .arg("--json")
        .output()
        .await
        .context("Failed to eval repos.nix")?;

    if !output.status.success() {
        return Ok(serde_json::json!({}));
    }

    let registry: serde_json::Value =
        serde_json::from_slice(&output.stdout).unwrap_or(serde_json::json!({}));
    Ok(registry)
}

/// Compute `--override-input` flags for local repo checkouts.
pub async fn local_override_args(repo_root: &Path) -> Result<Vec<String>> {
    let registry = get_repos_registry(repo_root).await?;
    let mut args = Vec::new();

    let Some(obj) = registry.as_object() else {
        return Ok(args);
    };

    let home = home_dir().unwrap_or_default();

    for (key, value) in obj {
        let flake_input = value
            .get("flakeInput")
            .and_then(|item| item.as_str())
            .unwrap_or("");
        if flake_input.is_empty() || flake_input == "null" {
            continue;
        }

        let name = key.rsplit('/').next().unwrap_or(key);
        let candidates = [
            home.join(".keystone").join("repos").join(key),
            repo_root.join(".repos").join(name),
            repo_root.join(".submodules").join(name),
            repo_root.join(name),
        ];

        for candidate in &candidates {
            if candidate.is_dir() {
                args.push("--override-input".to_string());
                args.push(flake_input.to_string());
                args.push(format!("path:{}", candidate.display()));
                break;
            }
        }
    }

    Ok(args)
}

/// Retrieve host metadata.
///
/// For `HostsNix` layout, evaluates `hosts.nix` directly.
/// For `FlakeHosts` layout, constructs HostInfo from flake evaluation.
pub async fn host_info(repo_root: &Path, host: &str) -> Result<HostInfo> {
    let layout = detect_layout(repo_root).context("Cannot detect repo layout")?;

    match &layout {
        RepoLayout::HostsNix(hosts_nix) => {
            let output = tokio::process::Command::new("nix")
                .args(["eval", "-f"])
                .arg(hosts_nix)
                .arg(host)
                .arg("--json")
                .output()
                .await
                .with_context(|| format!("Failed to read host info for {}", host))?;

            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                anyhow::bail!("Failed to evaluate host '{}': {}", host, stderr.trim());
            }

            serde_json::from_slice(&output.stdout)
                .with_context(|| format!("Failed to parse host metadata for {}", host))
        }
        RepoLayout::FlakeHosts(root) => {
            // Evaluate keystone.hosts.<key> from the flake config for full metadata.
            let mut cmd = tokio::process::Command::new("nix");
            cmd.arg("eval")
                .arg(format!(
                    "{}#nixosConfigurations.{}.config.keystone.hosts.\"{}\"",
                    root.display(),
                    host,
                    host,
                ))
                .arg("--json");
            for arg in local_override_args(repo_root).await? {
                cmd.arg(arg);
            }
            let output = cmd
                .output()
                .await
                .with_context(|| format!("Failed to read host info for {}", host))?;

            if output.status.success() {
                if let Ok(info) = serde_json::from_slice::<HostInfo>(&output.stdout) {
                    return Ok(info);
                }
            }

            // Fallback: construct minimal HostInfo from networking.hostName.
            let mut hn_cmd = tokio::process::Command::new("nix");
            hn_cmd
                .arg("eval")
                .arg(format!(
                    "{}#nixosConfigurations.{}.config.networking.hostName",
                    root.display(),
                    host,
                ))
                .arg("--raw");
            for arg in local_override_args(repo_root).await? {
                hn_cmd.arg(arg);
            }
            let hostname = hn_cmd
                .output()
                .await
                .ok()
                .filter(|o| o.status.success())
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_else(|| host.to_string());

            Ok(HostInfo {
                hostname,
                ssh_target: None,
                fallback_ip: None,
                role: None,
                host_public_key: None,
                build_on_remote: false,
            })
        }
    }
}

pub fn derive_ssh_target(hostname: &str, headscale_domain: &str) -> Option<String> {
    let hostname = hostname.trim();
    let headscale_domain = headscale_domain.trim();
    if hostname.is_empty() || headscale_domain.is_empty() {
        return None;
    }

    Some(format!("{}.{}", hostname, headscale_domain))
}

pub async fn resolve_ssh_target(
    repo_root: &Path,
    host: &str,
    info: &HostInfo,
) -> Result<Option<String>> {
    if let Some(target) = info
        .ssh_target
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return Ok(Some(target.to_string()));
    }

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("eval")
        .arg(format!(
            "{}#nixosConfigurations.{}.config.keystone.headscaleDomain",
            repo_root.display(),
            host,
        ))
        .arg("--raw");

    for arg in local_override_args(repo_root).await? {
        cmd.arg(arg);
    }

    let output = cmd
        .output()
        .await
        .with_context(|| format!("Failed to evaluate headscaleDomain for {}", host))?;

    if !output.status.success() {
        return Ok(None);
    }

    let headscale_domain = String::from_utf8_lossy(&output.stdout);
    Ok(derive_ssh_target(&info.hostname, &headscale_domain))
}

pub async fn list_hm_users(repo_root: &Path, host: &str) -> Result<Vec<String>> {
    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("eval")
        .arg(format!(
            "{}#nixosConfigurations.{}.config.home-manager.users",
            repo_root.display(),
            host,
        ))
        .arg("--apply")
        .arg("builtins.attrNames")
        .arg("--json");

    for arg in local_override_args(repo_root).await? {
        cmd.arg(arg);
    }

    let output = cmd
        .output()
        .await
        .context("Failed to list home-manager users")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "Failed to list home-manager users for {}: {}",
            host,
            stderr.trim()
        );
    }

    serde_json::from_slice(&output.stdout)
        .with_context(|| format!("Failed to parse home-manager users for {}", host))
}

async fn eval_hm_user_attr_json(
    repo_root: &Path,
    host: &str,
    user: &str,
    attr_suffix: &str,
) -> Result<serde_json::Value> {
    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("eval")
        .arg(format!(
            "{}#nixosConfigurations.{}.config.home-manager.users.\"{}\".{}",
            repo_root.display(),
            host,
            user,
            attr_suffix,
        ))
        .arg("--json");

    for arg in local_override_args(repo_root).await? {
        cmd.arg(arg);
    }

    let output = cmd
        .output()
        .await
        .with_context(|| format!("Failed to evaluate {} for {}", attr_suffix, user))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "Failed to evaluate {} for {} on {}: {}",
            attr_suffix,
            user,
            host,
            stderr.trim()
        );
    }

    serde_json::from_slice(&output.stdout)
        .with_context(|| format!("Failed to parse {} for {}", attr_suffix, user))
}

pub async fn resolve_current_hm_user(repo_root: &Path, host: &str) -> Result<Option<String>> {
    let preferred_user = std::env::var("SUDO_USER")
        .ok()
        .or_else(|| std::env::var("USER").ok())
        .filter(|value| !value.is_empty())
        .or_else(|| {
            std::process::Command::new("id")
                .arg("-un")
                .output()
                .ok()
                .filter(|output| output.status.success())
                .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
                .filter(|value| !value.is_empty())
        })
        .unwrap_or_else(|| "root".to_string());

    let users = list_hm_users(repo_root, host).await?;
    if users.is_empty() {
        return Ok(None);
    }

    if users.iter().any(|user| user == &preferred_user) {
        return Ok(Some(preferred_user));
    }

    if let Some(user) = users.iter().find(|user| !user.starts_with("agent-")) {
        return Ok(Some(user.clone()));
    }

    Ok(users.first().cloned())
}

pub async fn resolve_ollama_enabled(
    repo_root: &Path,
    host: &str,
    user: Option<&str>,
) -> Result<bool> {
    let user = match user {
        Some(user) if !user.is_empty() => user.to_string(),
        _ => resolve_current_hm_user(repo_root, host)
            .await?
            .ok_or_else(|| {
                anyhow::anyhow!("could not resolve a home-manager user for '{}'", host)
            })?,
    };

    Ok(
        eval_hm_user_attr_json(repo_root, host, &user, "keystone.terminal.ai.ollama.enable")
            .await?
            .as_bool()
            .unwrap_or(false),
    )
}

pub async fn resolve_ollama_host(
    repo_root: &Path,
    host: &str,
    user: Option<&str>,
) -> Result<String> {
    let user = match user {
        Some(user) if !user.is_empty() => user.to_string(),
        _ => resolve_current_hm_user(repo_root, host)
            .await?
            .ok_or_else(|| {
                anyhow::anyhow!("could not resolve a home-manager user for '{}'", host)
            })?,
    };

    Ok(
        eval_hm_user_attr_json(repo_root, host, &user, "keystone.terminal.ai.ollama.host")
            .await?
            .as_str()
            .unwrap_or_default()
            .to_string(),
    )
}

pub async fn resolve_ollama_default_model(
    repo_root: &Path,
    host: &str,
    user: Option<&str>,
) -> Result<String> {
    let user = match user {
        Some(user) if !user.is_empty() => user.to_string(),
        _ => resolve_current_hm_user(repo_root, host)
            .await?
            .ok_or_else(|| {
                anyhow::anyhow!("could not resolve a home-manager user for '{}'", host)
            })?,
    };

    Ok(eval_hm_user_attr_json(
        repo_root,
        host,
        &user,
        "keystone.terminal.ai.ollama.defaultModel",
    )
    .await?
    .as_str()
    .unwrap_or_default()
    .to_string())
}

pub async fn keystone_development_enabled(repo_root: &Path) -> Result<bool> {
    let Some(current_host) = resolve_current_host(repo_root).await? else {
        return Ok(false);
    };

    let output = tokio::process::Command::new("nix")
        .arg("eval")
        .arg(format!(
            "{}#nixosConfigurations.{}.config.keystone.development",
            repo_root.display(),
            current_host,
        ))
        .arg("--json")
        .output()
        .await
        .context("Failed to evaluate keystone.development")?;

    if !output.status.success() {
        return Ok(false);
    }

    Ok(serde_json::from_slice::<bool>(&output.stdout).unwrap_or(false))
}

pub async fn list_target_hm_users(
    repo_root: &Path,
    host: &str,
    user_filter: Option<&str>,
    all_users: bool,
) -> Result<Vec<String>> {
    let users = list_hm_users(repo_root, host).await?;
    if users.is_empty() {
        return Ok(Vec::new());
    }

    if let Some(filter) = user_filter.filter(|value| !value.is_empty()) {
        let mut matched = Vec::new();
        for requested_user in filter
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let Some(found) = users.iter().find(|available| available == &requested_user) else {
                anyhow::bail!(
                    "home-manager user '{}' is not configured on host '{}'",
                    requested_user,
                    host
                );
            };
            matched.push(found.clone());
        }
        return Ok(matched);
    }

    if all_users {
        return Ok(users);
    }

    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let info = host_info(repo_root, host).await?;
    if info.hostname == current_hostname {
        if let Some(user) = resolve_current_hm_user(repo_root, host).await? {
            return Ok(vec![user]);
        }
    }

    Ok(users)
}

/// Discover repos on disk in ~/.keystone/repos/ that are valid git repositories.
pub async fn discover_repos() -> Result<Vec<KeystoneRepo>> {
    let repos_dir = repos_dir()?;
    if !repos_dir.exists() {
        return Ok(Vec::new());
    }

    let mut found = Vec::new();
    let mut entries = fs::read_dir(&repos_dir)
        .await
        .context("Failed to read ~/.keystone/repos/")?;

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let git_dir = path.join(".git");
        if git_dir.exists() {
            let name = entry.file_name().to_string_lossy().to_string();
            found.push(KeystoneRepo { name, path });
        }
    }

    found.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(found)
}

/// Import an existing git repository. If the directory already exists and is
/// a valid git repo, reuse it instead of failing.
pub async fn import_repo(repo_name: String, git_url: String) -> Result<KeystoneRepo> {
    let repos_dir = repos_dir()?;
    fs::create_dir_all(&repos_dir)
        .await
        .context("Failed to create ~/.keystone/repos directory")?;

    let target_path = repos_dir.join(&repo_name);

    if target_path.exists() {
        let check_path = target_path.clone();
        let is_repo =
            tokio::task::spawn_blocking(move || git2::Repository::open(&check_path).is_ok())
                .await
                .unwrap_or(false);

        if is_repo {
            return Ok(KeystoneRepo {
                name: repo_name,
                path: target_path,
            });
        }

        anyhow::bail!(
            "Directory exists but is not a git repository: {}",
            target_path.display()
        );
    }

    let clone_target = target_path.clone();
    let repo_path = tokio::task::spawn_blocking(move || {
        git2::Repository::clone(&git_url, &clone_target)
            .map(|repo| repo.path().to_path_buf())
            .context(format!("Failed to clone repository from {}", git_url))
    })
    .await
    .context("Failed to spawn blocking task for git clone")??;

    let actual_repo_path = repo_path
        .parent()
        .context("Cloned repository path has no parent directory")?
        .to_path_buf();

    let submodule_output = tokio::process::Command::new("git")
        .args(["submodule", "update", "--init", "--recursive"])
        .current_dir(&actual_repo_path)
        .output()
        .await
        .context("Failed to run git submodule update")?;

    if !submodule_output.status.success() {
        let stderr = String::from_utf8_lossy(&submodule_output.stderr);
        anyhow::bail!("git submodule update failed: {}", stderr);
    }

    Ok(KeystoneRepo {
        name: repo_name,
        path: actual_repo_path,
    })
}

/// Create a new repository from the Keystone flake template.
pub async fn create_new_repo(repo_name: String) -> Result<KeystoneRepo> {
    let repos_dir = repos_dir()?;
    fs::create_dir_all(&repos_dir)
        .await
        .context("Failed to create ~/.keystone/repos directory")?;

    let target_path = repos_dir.join(&repo_name);

    if target_path.exists() {
        anyhow::bail!(
            "Repository directory already exists: {}",
            target_path.display()
        );
    }

    fs::create_dir(&target_path).await.context(format!(
        "Failed to create directory for new repo: {}",
        target_path.display()
    ))?;

    let output = tokio::process::Command::new("nix")
        .arg("flake")
        .arg("init")
        .arg("-t")
        .arg("github:ncrmro/keystone")
        .current_dir(&target_path)
        .output()
        .await
        .context("Failed to execute nix flake init command")?;

    if !output.status.success() {
        anyhow::bail!(
            "nix flake init failed: {}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    Ok(KeystoneRepo {
        name: repo_name.clone(),
        path: target_path,
    })
}

/// Create a new repository with programmatically generated Nix configuration.
#[allow(clippy::too_many_arguments)]
pub async fn create_new_repo_from_config(
    repo_name: String,
    machine_type: crate::template::MachineType,
    hostname: String,
    storage_type: crate::template::StorageType,
    disk_device: Option<String>,
    username: String,
    password: String,
    github_username: Option<String>,
    authorized_keys: Vec<String>,
    time_zone: Option<String>,
    state_version: Option<String>,
) -> Result<KeystoneRepo> {
    use crate::template;

    let repos_dir = repos_dir()?;
    fs::create_dir_all(&repos_dir)
        .await
        .context("Failed to create ~/.keystone/repos directory")?;

    let target_path = repos_dir.join(&repo_name);

    if target_path.exists() {
        anyhow::bail!(
            "Repository directory already exists: {}",
            target_path.display()
        );
    }

    fs::create_dir(&target_path).await.context(format!(
        "Failed to create directory for new repo: {}",
        target_path.display()
    ))?;

    let config = template::GenerateConfig {
        hostname: hostname.clone(),
        machine_type,
        storage_type,
        disk_device,
        github_username,
        time_zone: time_zone.unwrap_or_else(|| "UTC".to_string()),
        state_version: state_version.unwrap_or_else(|| "25.05".to_string()),
        user: template::UserConfig {
            username,
            password,
            authorized_keys: authorized_keys.clone(),
        },
        remote_unlock: template::RemoteUnlockConfig {
            enable: machine_type == template::MachineType::Server,
            authorized_keys,
        },
        owner_name: None,
        owner_email: None,
    };

    let flake_nix = template::generate_flake_nix(&config);
    let configuration_nix = template::generate_configuration_nix(&config);
    let hardware_nix = template::generate_hardware_nix(&config);

    let host_dir = target_path.join("hosts").join(&hostname);
    fs::create_dir_all(&host_dir)
        .await
        .context("Failed to create hosts/<hostname> directory")?;

    fs::write(target_path.join("flake.nix"), flake_nix)
        .await
        .context("Failed to write flake.nix")?;
    fs::write(host_dir.join("configuration.nix"), configuration_nix)
        .await
        .context("Failed to write configuration.nix")?;
    fs::write(host_dir.join("hardware.nix"), hardware_nix)
        .await
        .context("Failed to write hardware.nix")?;

    let commit_path = target_path.clone();
    tokio::task::spawn_blocking(move || -> anyhow::Result<()> {
        let repo =
            git2::Repository::init(&commit_path).context("Failed to initialize git repository")?;

        let mut index = repo.index().context("Failed to open index")?;
        index
            .add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
            .context("Failed to add files to index")?;
        index.write().context("Failed to write index")?;
        let tree_id = index.write_tree().context("Failed to write tree")?;
        let tree = repo.find_tree(tree_id).context("Failed to find tree")?;

        let sig =
            git2::Signature::now("ks", "ks@localhost").context("Failed to create signature")?;
        repo.commit(
            Some("HEAD"),
            &sig,
            &sig,
            "feat: initial Keystone NixOS configuration",
            &tree,
            &[],
        )
        .context("Failed to create initial commit")?;

        Ok(())
    })
    .await
    .context("Failed to spawn git init task")??;

    Ok(KeystoneRepo {
        name: repo_name,
        path: target_path,
    })
}

/// Create a private GitHub repository and set it as the origin remote.
pub async fn create_github_repo(repo_path: &std::path::Path, repo_name: &str) -> Result<String> {
    let output = tokio::process::Command::new("gh")
        .args([
            "repo",
            "create",
            repo_name,
            "--private",
            "--source",
            ".",
            "--push",
        ])
        .current_dir(repo_path)
        .output()
        .await
        .context("Failed to run 'gh repo create' — is gh CLI installed and authenticated?")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("gh repo create failed: {}", stderr.trim());
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(stdout)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_flake_repo(path: &Path) {
        std::fs::create_dir_all(path.join("hosts")).unwrap();
        std::fs::write(path.join("flake.nix"), "{ }").unwrap();
    }

    #[test]
    fn derive_ssh_target_requires_values() {
        assert_eq!(derive_ssh_target("", "tail.example.ts.net"), None);
        assert_eq!(derive_ssh_target("laptop", ""), None);
    }

    #[test]
    fn derive_ssh_target_joins_hostname_and_domain() {
        assert_eq!(
            derive_ssh_target(" laptop ", " tail.example.ts.net "),
            Some("laptop.tail.example.ts.net".to_string())
        );
    }

    #[test]
    fn detect_layout_hosts_nix() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("hosts.nix"), "{}").unwrap();
        let layout = detect_layout(dir.path());
        assert!(matches!(layout, Some(RepoLayout::HostsNix(_))));
    }

    #[test]
    fn detect_layout_flake_hosts() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("flake.nix"), "{}").unwrap();
        std::fs::create_dir(dir.path().join("hosts")).unwrap();
        let layout = detect_layout(dir.path());
        assert!(matches!(layout, Some(RepoLayout::FlakeHosts(_))));
    }

    #[test]
    fn detect_layout_prefers_hosts_nix() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("hosts.nix"), "{}").unwrap();
        std::fs::write(dir.path().join("flake.nix"), "{}").unwrap();
        std::fs::create_dir(dir.path().join("hosts")).unwrap();
        // When both exist, hosts.nix takes precedence.
        let layout = detect_layout(dir.path());
        assert!(matches!(layout, Some(RepoLayout::HostsNix(_))));
    }

    #[test]
    fn detect_layout_empty_dir() {
        let dir = tempfile::tempdir().unwrap();
        assert!(detect_layout(dir.path()).is_none());
    }

    #[test]
    fn canonical_installed_repo_path_for_builds_expected_location() {
        let home = Path::new("/home/noah");
        assert_eq!(
            canonical_installed_repo_path_for(home, "noah"),
            PathBuf::from("/home/noah/.keystone/repos/noah/keystone-config")
        );
    }

    #[test]
    fn find_repo_with_context_prefers_system_flake_env_over_canonical() {
        let home = tempfile::tempdir().unwrap();
        let canonical_repo = canonical_installed_repo_path(home.path()).unwrap();
        let override_repo = home.path().join("override-repo");

        write_flake_repo(&canonical_repo);
        write_flake_repo(&override_repo);

        let repo =
            find_repo_with_context(home.path(), None, None, Some(override_repo.as_path())).unwrap();

        assert_eq!(repo, std::fs::canonicalize(&override_repo).unwrap());
    }

    #[test]
    fn find_repo_with_context_falls_back_to_canonical_repo() {
        let home = tempfile::tempdir().unwrap();
        let canonical_repo = canonical_installed_repo_path(home.path()).unwrap();

        write_flake_repo(&canonical_repo);

        let repo = find_repo_with_context(home.path(), None, None, None).unwrap();

        assert_eq!(repo, std::fs::canonicalize(&canonical_repo).unwrap());
    }

    #[test]
    fn find_config_repo_recursive_rejects_modules_hosts_nix() {
        // Reproduces the bug where `keystone/modules/hosts.nix` (a NixOS module
        // options file) was mistakenly treated as a config repo root. A directory
        // only qualifies when it has `flake.nix` alongside `hosts.nix` or `hosts/`.
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();

        // Fake keystone checkout: has flake.nix at top, hosts.nix only inside modules/.
        let keystone = root.join("owner").join("keystone");
        std::fs::create_dir_all(keystone.join("modules")).unwrap();
        std::fs::write(keystone.join("flake.nix"), "{}").unwrap();
        std::fs::write(keystone.join("modules").join("hosts.nix"), "{}").unwrap();

        // Real config repo: flake.nix + hosts.nix at same level.
        let real = root.join("owner").join("real-config");
        std::fs::create_dir_all(&real).unwrap();
        std::fs::write(real.join("flake.nix"), "{}").unwrap();
        std::fs::write(real.join("hosts.nix"), "{}").unwrap();

        let found = find_config_repo_recursive(root, 5).expect("walker should find real-config");
        assert_eq!(found, std::fs::canonicalize(&real).unwrap());
    }

    #[test]
    fn find_config_repo_recursive_rejects_bare_hosts_nix_without_flake() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        let bare = root.join("owner").join("stray");
        std::fs::create_dir_all(&bare).unwrap();
        std::fs::write(bare.join("hosts.nix"), "{}").unwrap();

        assert!(find_config_repo_recursive(root, 5).is_none());
    }

    #[test]
    fn find_config_repo_recursive_accepts_flake_plus_hosts_dir() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        let repo = root.join("owner").join("cfg");
        std::fs::create_dir_all(repo.join("hosts")).unwrap();
        std::fs::write(repo.join("flake.nix"), "{}").unwrap();

        let found = find_config_repo_recursive(root, 5).expect("walker should find cfg");
        assert_eq!(found, std::fs::canonicalize(&repo).unwrap());
    }

    #[test]
    fn find_repo_with_context_reports_invalid_system_flake_env() {
        let home = tempfile::tempdir().unwrap();
        let invalid_repo = home.path().join("missing-repo");

        let error = find_repo_with_context(home.path(), None, None, Some(invalid_repo.as_path()))
            .unwrap_err();

        assert!(error.to_string().contains("KEYSTONE_SYSTEM_FLAKE"));
        assert!(error
            .to_string()
            .contains(&invalid_repo.display().to_string()));
    }
}
