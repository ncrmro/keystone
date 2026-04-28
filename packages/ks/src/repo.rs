//! Repository management operations for ks.

use anyhow::{Context, Result};
use home::home_dir;
use serde::Deserialize;
use std::path::{Path, PathBuf};
use tokio::fs;

use crate::config::KeystoneRepo;

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
///
/// `flake.nix` is required for all layouts. A bare `hosts.nix` without
/// `flake.nix` is no longer recognised.
pub fn detect_layout(repo_root: &Path) -> Option<RepoLayout> {
    if !repo_root.join("flake.nix").is_file() {
        return None;
    }
    let hosts_nix = repo_root.join("hosts.nix");
    if hosts_nix.is_file() {
        return Some(RepoLayout::HostsNix(hosts_nix));
    }
    if repo_root.join("hosts").is_dir() {
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

/// Validate that `path` is a recognised Keystone config repo and return its
/// canonical form, or `None` if the layout is not recognised or exposes no
/// hosts.
///
/// This performs a cheap structural check (`flake.nix` + either `hosts.nix`
/// or `hosts/`), then — unless `KS_SKIP_REPO_NIX_EVAL` is set — asserts that
/// the flake exposes a non-empty `nixosConfigurations` attrset. The env var
/// exists so tests can stub repos without a working Nix evaluator.
///
/// CRITICAL: never mistake a keystone platform repo (or worktree of one) for a
/// consumer config flake — keystone's `modules/hosts.nix` is a NixOS options
/// module (a lambda) that will later blow up `nix eval` with "expected a set
/// but found a function".
fn validate_repo_path(path: &Path) -> Option<PathBuf> {
    if looks_like_keystone_repo(path) {
        return None;
    }
    detect_layout(path)?;
    let canonical = std::fs::canonicalize(path)
        .ok()
        .unwrap_or_else(|| path.to_path_buf());

    if std::env::var_os("KS_SKIP_REPO_NIX_EVAL").is_some() {
        return Some(canonical);
    }

    // Assert that `<path>#nixosConfigurations` evaluates to a non-empty
    // attrset. This catches the "stub flake with no hosts" regression that a
    // pure file-presence check misses.
    let output = std::process::Command::new("nix")
        .arg("eval")
        .arg(format!("{}#nixosConfigurations", canonical.display()))
        .args([
            "--apply",
            "a: builtins.length (builtins.attrNames a)",
            "--json",
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }
    let count: u64 = serde_json::from_slice(&output.stdout).ok()?;
    if count == 0 {
        return None;
    }
    Some(canonical)
}

/// Look up the home directory for `user` via `getent passwd`.
///
/// CRITICAL: under `sudo`, `$HOME` is typically `/root` while `$SUDO_USER`
/// names the invoker. Joining `$HOME` with `$SUDO_USER` would produce
/// `/root/.keystone/repos/<invoker>/keystone-config`, which contradicts the
/// canonical-path rule. We resolve the invoker's home through NSS so the
/// lookup keeps working with LDAP, sssd, and other passwd backends — not
/// just `/etc/passwd`.
fn lookup_user_home(user: &str) -> Option<PathBuf> {
    let output = std::process::Command::new("getent")
        .args(["passwd", user])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    // passwd format: name:passwd:uid:gid:gecos:home:shell — home is field 6.
    let line = std::str::from_utf8(&output.stdout)
        .ok()?
        .trim_end_matches('\n');
    let home = line.split(':').nth(5).filter(|value| !value.is_empty())?;
    Some(PathBuf::from(home))
}

/// Compute the canonical consumer-flake path for the current user.
///
/// The path is a deterministic function of the resolved user (`$SUDO_USER`
/// preferred, else `$USER`) and that user's actual home directory:
/// `<user-home>/.keystone/repos/<user>/keystone-config`. There is no pointer
/// file, environment override, or filesystem heuristic — every caller in the
/// codebase MUST agree on this single rule.
///
/// CRITICAL: under `sudo`, `$HOME` is `/root` while the consumer flake lives
/// under the invoker's home. When `$SUDO_USER` is set we resolve the home
/// directory from passwd (via `getent`) instead of trusting `$HOME`. When
/// only `$USER` is set we trust `$HOME` directly.
///
/// CRITICAL: the agent kept reinventing pointer-file resolution because it
/// matches NixOS training-corpus patterns. Do not reintroduce it here. See
/// `conventions/architecture.consumer-flake-path.md` and the
/// `consumer-flake-path-regression` flake check.
pub fn canonical_consumer_flake_path() -> Result<PathBuf> {
    let sudo_user = std::env::var("SUDO_USER")
        .ok()
        .filter(|value| !value.is_empty());
    let env_user = std::env::var("USER").ok().filter(|value| !value.is_empty());
    let user = sudo_user.clone().or_else(|| env_user.clone()).context(
        "Cannot determine current user: $USER is unset.\n\
             The Keystone consumer flake lives at \
             $HOME/.keystone/repos/$USER/keystone-config.",
    )?;
    let home = match &sudo_user {
        Some(invoker) => lookup_user_home(invoker)
            .or_else(home_dir)
            .with_context(|| format!("Failed to resolve home directory for {invoker}"))?,
        None => home_dir().context("Failed to get home directory")?,
    };
    Ok(home
        .join(".keystone")
        .join("repos")
        .join(user)
        .join("keystone-config"))
}

/// Locate the active Keystone config repository at the canonical path.
///
/// The consumer flake MUST live at `$HOME/.keystone/repos/$USER/keystone-config`.
/// `ks` and all keystone shell scripts derive this path from `$USER` directly.
/// There is no pointer file, environment variable, or filesystem heuristic.
pub fn find_repo() -> Result<PathBuf> {
    let path = canonical_consumer_flake_path()?;
    validate_repo_path(&path).ok_or_else(|| {
        anyhow::anyhow!(
            "Keystone consumer flake not found at the canonical path: {}\n\
             Expected flake.nix + hosts/ (mkSystemFlake) or flake.nix + hosts.nix (legacy).\n\
             Clone or move your consumer flake to that location.",
            path.display()
        )
    })
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
pub(crate) mod tests {
    use super::*;

    fn write_flake_repo(path: &Path) {
        std::fs::create_dir_all(path.join("hosts")).unwrap();
        std::fs::write(path.join("flake.nix"), "{ }").unwrap();
    }

    /// Guard: every test that calls `find_repo` or `validate_repo_path` with
    /// a stub flake.nix must skip the nix eval step, otherwise `nix eval`
    /// attempts to evaluate the empty attrset and fails. Production callers
    /// do not set this var; validation runs the real check there.
    ///
    /// CRITICAL: env mutation is process-global; serialise guard usage with
    /// a mutex so parallel tests don't observe each other's env state.
    static SKIP_NIX_EVAL_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    struct SkipNixEvalGuard(std::sync::MutexGuard<'static, ()>);
    impl SkipNixEvalGuard {
        fn new() -> Self {
            let lock = SKIP_NIX_EVAL_LOCK.lock().unwrap_or_else(|p| p.into_inner());
            std::env::set_var("KS_SKIP_REPO_NIX_EVAL", "1");
            Self(lock)
        }
    }
    impl Drop for SkipNixEvalGuard {
        fn drop(&mut self) {
            std::env::remove_var("KS_SKIP_REPO_NIX_EVAL");
        }
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

    // --- detect_layout tests ---

    #[test]
    fn detect_layout_requires_flake_nix() {
        // A bare hosts.nix without flake.nix must NOT be detected.
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("hosts.nix"), "{}").unwrap();
        assert!(detect_layout(dir.path()).is_none());
    }

    #[test]
    fn detect_layout_hosts_nix_with_flake() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("flake.nix"), "{}").unwrap();
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

    // --- canonical_consumer_flake_path / find_repo tests ---
    //
    // The path is a deterministic function of $USER and $HOME; we exercise
    // both at once by overriding HOME (and USER on hosts where SUDO_USER is
    // unset) to point at a fixture under tempfile.

    /// Crate-wide guard for tests that mutate $HOME, $USER, or $SUDO_USER.
    /// Cargo runs all #[test]s in a single process by default, so any test
    /// that pokes those env vars MUST acquire this lock to avoid racing
    /// the canonical-path tests in this module and the gate test in
    /// `cmd::update_menu::tests`. There is no per-module variant — every
    /// env-mutating test in the crate locks the same mutex.
    pub(crate) static USER_ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    /// Run `body` with $HOME and $USER overridden so the canonical path
    /// resolves to a tempfile-backed location. Restores the prior env on
    /// drop, with a process-wide mutex to keep parallel tests sane.
    fn with_user_env<F: FnOnce(&Path, &str)>(user: &str, body: F) {
        let _lock = USER_ENV_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let home = tempfile::tempdir().unwrap();
        let prior_home = std::env::var_os("HOME");
        let prior_user = std::env::var_os("USER");
        let prior_sudo_user = std::env::var_os("SUDO_USER");
        std::env::set_var("HOME", home.path());
        std::env::set_var("USER", user);
        // SUDO_USER takes precedence over USER in canonical_consumer_flake_path,
        // so explicitly clear it for tests that want to control the result.
        std::env::remove_var("SUDO_USER");
        body(home.path(), user);
        if let Some(value) = prior_home {
            std::env::set_var("HOME", value);
        } else {
            std::env::remove_var("HOME");
        }
        if let Some(value) = prior_user {
            std::env::set_var("USER", value);
        } else {
            std::env::remove_var("USER");
        }
        if let Some(value) = prior_sudo_user {
            std::env::set_var("SUDO_USER", value);
        }
    }

    #[test]
    fn canonical_consumer_flake_path_uses_user_and_home() {
        with_user_env("alice", |home, _| {
            let path = canonical_consumer_flake_path().unwrap();
            assert_eq!(
                path,
                home.join(".keystone")
                    .join("repos")
                    .join("alice")
                    .join("keystone-config")
            );
        });
    }

    #[test]
    fn canonical_consumer_flake_path_prefers_sudo_user() {
        // SUDO_USER must win over USER for the username component of the
        // path. We use a deliberately-nonexistent invoker so `getent` fails
        // and the resolver falls back to $HOME (which the test controls).
        // A separate test exercises the real getent lookup path against the
        // running process's own user.
        let _lock = USER_ENV_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let home = tempfile::tempdir().unwrap();
        let prior_home = std::env::var_os("HOME");
        let prior_user = std::env::var_os("USER");
        let prior_sudo_user = std::env::var_os("SUDO_USER");
        std::env::set_var("HOME", home.path());
        std::env::set_var("USER", "root");
        // CRITICAL: this username must be guaranteed-absent from passwd, or
        // the assertion below would compare against an unrelated home.
        std::env::set_var("SUDO_USER", "ks-test-nonexistent-invoker");

        let path = canonical_consumer_flake_path().unwrap();
        assert_eq!(
            path,
            home.path()
                .join(".keystone")
                .join("repos")
                .join("ks-test-nonexistent-invoker")
                .join("keystone-config"),
            "SUDO_USER must win over USER so `sudo ks` still resolves the invoker's checkout"
        );

        if let Some(value) = prior_home {
            std::env::set_var("HOME", value);
        } else {
            std::env::remove_var("HOME");
        }
        if let Some(value) = prior_user {
            std::env::set_var("USER", value);
        } else {
            std::env::remove_var("USER");
        }
        if let Some(value) = prior_sudo_user {
            std::env::set_var("SUDO_USER", value);
        } else {
            std::env::remove_var("SUDO_USER");
        }
    }

    #[test]
    fn canonical_consumer_flake_path_uses_invoker_home_under_sudo() {
        // Real-world contract: under `sudo` $HOME is /root but the consumer
        // flake lives in the invoker's home. We resolve the invoker's home
        // via passwd (getent). This test exercises that path against the
        // running process's actual user so we don't need to mock getent.
        let Some(real_user) = std::process::Command::new("id")
            .arg("-un")
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
            .filter(|value| !value.is_empty())
        else {
            eprintln!("skipping: cannot determine current user via id -un");
            return;
        };
        // Skip when getent is not available on PATH (Nix sandbox builds).
        if std::process::Command::new("getent")
            .args(["passwd", &real_user])
            .output()
            .map(|o| !o.status.success())
            .unwrap_or(true)
        {
            eprintln!("skipping: getent passwd {real_user} not resolvable");
            return;
        }
        let Some(real_home) = lookup_user_home(&real_user) else {
            eprintln!("skipping: lookup_user_home returned None");
            return;
        };

        let _lock = USER_ENV_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let prior_home = std::env::var_os("HOME");
        let prior_user = std::env::var_os("USER");
        let prior_sudo_user = std::env::var_os("SUDO_USER");
        // Simulate a sudo invocation: HOME=/root, USER=root, SUDO_USER=invoker.
        std::env::set_var("HOME", "/root");
        std::env::set_var("USER", "root");
        std::env::set_var("SUDO_USER", &real_user);

        let path = canonical_consumer_flake_path().unwrap();
        let expected = real_home
            .join(".keystone")
            .join("repos")
            .join(&real_user)
            .join("keystone-config");
        assert_eq!(
            path, expected,
            "under sudo, the consumer-flake path must root at the invoker's home, not /root"
        );

        if let Some(value) = prior_home {
            std::env::set_var("HOME", value);
        } else {
            std::env::remove_var("HOME");
        }
        if let Some(value) = prior_user {
            std::env::set_var("USER", value);
        } else {
            std::env::remove_var("USER");
        }
        if let Some(value) = prior_sudo_user {
            std::env::set_var("SUDO_USER", value);
        } else {
            std::env::remove_var("SUDO_USER");
        }
    }

    #[test]
    fn find_repo_resolves_canonical_layout() {
        let _guard = SkipNixEvalGuard::new();
        with_user_env("alice", |home, user| {
            let repo = home
                .join(".keystone")
                .join("repos")
                .join(user)
                .join("keystone-config");
            std::fs::create_dir_all(&repo).unwrap();
            write_flake_repo(&repo);

            let found = find_repo().unwrap();
            assert_eq!(found, std::fs::canonicalize(&repo).unwrap());
        });
    }

    #[test]
    fn find_repo_errors_when_canonical_path_missing() {
        with_user_env("alice", |_home, _| {
            // Don't create the repo at all.
            let err = find_repo().unwrap_err();
            let msg = err.to_string();
            assert!(
                msg.contains("canonical path"),
                "expected error to mention canonical path, got: {msg}"
            );
        });
    }

    #[test]
    fn validate_repo_path_rejects_empty_nixos_configurations() {
        // A stub flake.nix with no nixosConfigurations must be rejected by
        // the real (non-skip) validation path. This requires `nix` on PATH;
        // the check fails closed if nix returns non-zero, which is the
        // behaviour we want — a stub repo MUST NOT validate.
        if std::process::Command::new("nix")
            .arg("--version")
            .output()
            .map(|o| !o.status.success())
            .unwrap_or(true)
        {
            eprintln!("skipping: nix not available");
            return;
        }
        // Hold the shared env lock so a parallel test with
        // SkipNixEvalGuard doesn't mask our un-set state.
        let _lock = SKIP_NIX_EVAL_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        std::env::remove_var("KS_SKIP_REPO_NIX_EVAL");
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("hosts")).unwrap();
        std::fs::write(dir.path().join("flake.nix"), "{ outputs = _: { }; }").unwrap();
        assert!(
            validate_repo_path(dir.path()).is_none(),
            "stub flake with no nixosConfigurations must not validate"
        );
    }

    /// Create a directory layout that looks like a keystone platform repo:
    /// flake.nix + docs/ks.md + packages/ks/ + modules/hosts.nix.
    fn write_keystone_like_repo(path: &Path) {
        std::fs::create_dir_all(path.join("docs")).unwrap();
        std::fs::create_dir_all(path.join("packages").join("ks")).unwrap();
        std::fs::create_dir_all(path.join("modules")).unwrap();
        std::fs::write(path.join("flake.nix"), "{ }").unwrap();
        std::fs::write(path.join("docs").join("ks.md"), "").unwrap();
        // Mimic keystone's lambda-typed options module.
        std::fs::write(
            path.join("modules").join("hosts.nix"),
            "{ config, lib, ... }: { }\n",
        )
        .unwrap();
    }

    #[test]
    fn validate_repo_path_rejects_keystone_platform_repo() {
        let _guard = SkipNixEvalGuard::new();
        let dir = tempfile::tempdir().unwrap();
        write_keystone_like_repo(dir.path());
        // Even if a keystone repo happens to have hosts.nix or hosts/ at root,
        // treat it as the platform repo, not a consumer config.
        std::fs::write(dir.path().join("hosts.nix"), "{ }").unwrap();
        assert!(validate_repo_path(dir.path()).is_none());
    }

    #[test]
    fn find_repo_rejects_module_function_hosts_nix() {
        let _guard = SkipNixEvalGuard::new();
        // A directory with only hosts.nix (no flake.nix) must be rejected —
        // this is the module-function-masquerading-as-attrset bug. The fix
        // lives in detect_layout, which now requires flake.nix; verifying it
        // through validate_repo_path covers the full surface that find_repo
        // itself exercises after #461.
        with_user_env("alice", |home, user| {
            let repo = home
                .join(".keystone")
                .join("repos")
                .join(user)
                .join("keystone-config");
            std::fs::create_dir_all(&repo).unwrap();
            std::fs::write(repo.join("hosts.nix"), "{ config, ... }: {}").unwrap();
            // No flake.nix at the canonical path → find_repo errors.
            assert!(validate_repo_path(&repo).is_none());
            let err = find_repo().unwrap_err();
            assert!(err.to_string().contains("canonical path"));
        });
    }
}
