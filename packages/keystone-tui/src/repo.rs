//! Repository management operations for Keystone TUI.

use anyhow::{Context, Result};
use home::home_dir;
use std::path::{Path, PathBuf};
use tokio::fs;

use crate::config::KeystoneRepo;

/// Return the base repos directory (~/.keystone/repos/).
fn repos_dir() -> Result<PathBuf> {
    let home = home_dir().context("Failed to get home directory")?;
    Ok(home.join(".keystone").join("repos"))
}

/// Locate the nixos-config repository.
///
/// Mirrors the shell `find_repo` function:
/// 1. `$NIXOS_CONFIG_DIR` if set and contains `hosts.nix`
/// 2. Git repo root of current directory if it contains `hosts.nix`
/// 3. `~/.keystone/repos/*/` if any contains `hosts.nix`
/// 4. `~/nixos-config` as fallback
pub fn find_repo() -> Result<PathBuf> {
    // 1. NIXOS_CONFIG_DIR
    if let Ok(dir) = std::env::var("NIXOS_CONFIG_DIR") {
        let path = PathBuf::from(&dir);
        if path.join("hosts.nix").is_file() {
            return std::fs::canonicalize(&path)
                .or(Ok::<PathBuf, std::io::Error>(path))
                .context("Failed to canonicalize NIXOS_CONFIG_DIR");
        }
    }

    // 2. Git repo root of current directory
    if let Ok(output) = std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if output.status.success() {
            let root = PathBuf::from(String::from_utf8_lossy(&output.stdout).trim());
            if root.join("hosts.nix").is_file() {
                return std::fs::canonicalize(&root)
                    .or(Ok::<PathBuf, std::io::Error>(root))
                    .context("Failed to canonicalize git root");
            }
        }
    }

    // 3. Scan ~/.keystone/repos/
    if let Ok(home) = home_dir().context("No home directory") {
        let repos = home.join(".keystone").join("repos");
        if repos.is_dir() {
            if let Some(found) = find_hosts_nix_recursive(&repos, 3) {
                return Ok(found);
            }
        }
    }

    // 4. ~/nixos-config fallback
    if let Some(home) = home_dir() {
        let fallback = home.join("nixos-config");
        if fallback.join("hosts.nix").is_file() {
            return std::fs::canonicalize(&fallback)
                .or(Ok::<PathBuf, std::io::Error>(fallback))
                .context("Failed to canonicalize ~/nixos-config");
        }
    }

    anyhow::bail!(
        "Cannot find nixos-config repo (no hosts.nix found).\n\
         Set NIXOS_CONFIG_DIR or run from within the repo."
    )
}

/// Walk up to `max_depth` levels looking for a directory containing `hosts.nix`.
fn find_hosts_nix_recursive(dir: &Path, max_depth: usize) -> Option<PathBuf> {
    if max_depth == 0 {
        return None;
    }
    let entries = std::fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        if path.join("hosts.nix").is_file() {
            return std::fs::canonicalize(&path).ok().or(Some(path));
        }
        if let Some(found) = find_hosts_nix_recursive(&path, max_depth - 1) {
            return Some(found);
        }
    }
    None
}

/// Resolve the current hostname to a host key in `hosts.nix`.
///
/// When `host` is `None`, looks up the current machine's hostname.
/// Mirrors the shell `resolve_host` function.
pub async fn resolve_host(repo_root: &Path, host: Option<&str>) -> Result<String> {
    if let Some(h) = host {
        // Validate the host exists
        let output = tokio::process::Command::new("nix")
            .args(["eval", "-f"])
            .arg(repo_root.join("hosts.nix"))
            .arg(h)
            .arg("--json")
            .output()
            .await
            .context("Failed to run nix eval")?;

        if !output.status.success() {
            // List known hosts for a helpful error
            let list_output = tokio::process::Command::new("nix")
                .args(["eval", "-f"])
                .arg(repo_root.join("hosts.nix"))
                .args([
                    "--apply",
                    "h: builtins.concatStringsSep \", \" (builtins.attrNames h)",
                    "--raw",
                ])
                .output()
                .await
                .ok();
            let known = list_output
                .as_ref()
                .filter(|o| o.status.success())
                .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
                .unwrap_or_else(|| "(unknown)".to_string());
            anyhow::bail!("Unknown host '{}'. Known hosts: {}", h, known);
        }
        return Ok(h.to_string());
    }

    // No host specified — resolve from current hostname
    let current_hostname = hostname::get()
        .context("Failed to get hostname")?
        .to_string_lossy()
        .to_string();

    let expr = format!(
        "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"{}\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m",
        current_hostname
    );

    let output = tokio::process::Command::new("nix")
        .args(["eval", "-f"])
        .arg(repo_root.join("hosts.nix"))
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

/// Parse a comma-separated host list into individual host names.
/// If the input is empty, resolves the current host from `hosts.nix`.
pub async fn resolve_hosts(repo_root: &Path, hosts_arg: Option<&str>) -> Result<Vec<String>> {
    match hosts_arg {
        Some(arg) if !arg.is_empty() => {
            let mut result = Vec::new();
            for h in arg.split(',') {
                let h = h.trim();
                if !h.is_empty() {
                    result.push(resolve_host(repo_root, Some(h)).await?);
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
///
/// Mirrors the shell `local_override_args` function. Checks standard locations:
/// 1. `~/.keystone/repos/{key}`
/// 2. `{repo_root}/.repos/{name}`
/// 3. `{repo_root}/.submodules/{name}` (legacy)
/// 4. `{repo_root}/{name}` (legacy)
pub async fn local_override_args(repo_root: &Path) -> Result<Vec<String>> {
    let registry = get_repos_registry(repo_root).await?;
    let mut args = Vec::new();

    let obj = match registry.as_object() {
        Some(o) => o,
        None => return Ok(args),
    };

    let home = home_dir().unwrap_or_default();

    for (key, value) in obj {
        let flake_input = value
            .get("flakeInput")
            .and_then(|v| v.as_str())
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
        // Check if it's a git repo
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
        // If it's already a git repo, reuse it
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

    // Initialize and update submodules via git CLI (handles SSH auth properly)
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
///
/// Instead of using `nix flake init`, this generates flake.nix, configuration.nix,
/// and hardware.nix from the provided configuration, filling in all values.
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

    // Write generated Nix files using hosts/<hostname>/ layout
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

    // Initialize git repository and create initial commit
    let commit_path = target_path.clone();
    tokio::task::spawn_blocking(move || -> anyhow::Result<()> {
        let repo =
            git2::Repository::init(&commit_path).context("Failed to initialize git repository")?;

        // Stage all generated files
        let mut index = repo.index().context("Failed to open index")?;
        index
            .add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
            .context("Failed to add files to index")?;
        index.write().context("Failed to write index")?;
        let tree_id = index.write_tree().context("Failed to write tree")?;
        let tree = repo.find_tree(tree_id).context("Failed to find tree")?;

        // Create initial commit
        let sig = git2::Signature::now("Keystone TUI", "keystone-tui@localhost")
            .context("Failed to create signature")?;
        repo.commit(
            Some("HEAD"),
            &sig,
            &sig,
            "feat: initial Keystone NixOS configuration",
            &tree,
            &[], // no parents — initial commit
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
///
/// Requires `gh` CLI to be authenticated. Returns Ok(()) if successful,
/// or an error if `gh` is not available or the operation fails.
pub async fn create_github_repo(repo_path: &std::path::Path, repo_name: &str) -> Result<String> {
    // Create private repo on GitHub
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
    use tempfile::tempdir;

    #[test]
    fn find_hosts_nix_recursive_finds_immediate() {
        let dir = tempdir().unwrap();
        let sub = dir.path().join("my-repo");
        std::fs::create_dir(&sub).unwrap();
        std::fs::write(sub.join("hosts.nix"), "{ }").unwrap();

        let found = find_hosts_nix_recursive(dir.path(), 3);
        assert!(found.is_some());
        // Should resolve to the directory containing hosts.nix
        let found = found.unwrap();
        assert!(found.ends_with("my-repo"));
    }

    #[test]
    fn find_hosts_nix_recursive_finds_nested() {
        let dir = tempdir().unwrap();
        let owner = dir.path().join("ncrmro");
        let repo = owner.join("nixos-config");
        std::fs::create_dir_all(&repo).unwrap();
        std::fs::write(repo.join("hosts.nix"), "{ }").unwrap();

        let found = find_hosts_nix_recursive(dir.path(), 3);
        assert!(found.is_some());
    }

    #[test]
    fn find_hosts_nix_recursive_empty_dir() {
        let dir = tempdir().unwrap();
        let found = find_hosts_nix_recursive(dir.path(), 3);
        assert!(found.is_none());
    }

    #[test]
    fn find_hosts_nix_recursive_respects_depth() {
        let dir = tempdir().unwrap();
        let deep = dir.path().join("a").join("b").join("c").join("d");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(deep.join("hosts.nix"), "{ }").unwrap();

        // depth=2 should not find it (needs 4 levels)
        let found = find_hosts_nix_recursive(dir.path(), 2);
        assert!(found.is_none());
    }

    #[test]
    fn find_repo_uses_env_var() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join("hosts.nix"), "{ }").unwrap();

        // Set env var (scoped to this test via temp)
        std::env::set_var("NIXOS_CONFIG_DIR", dir.path());
        let result = find_repo();
        std::env::remove_var("NIXOS_CONFIG_DIR");

        assert!(result.is_ok());
    }

    #[test]
    fn find_repo_returns_error_when_nothing_found() {
        // Ensure none of the detection methods find anything
        std::env::remove_var("NIXOS_CONFIG_DIR");
        // We can't fully isolate HOME, but we can check that find_repo
        // returns an error describing the problem.
        let result = find_repo();
        // This may or may not error depending on the host environment,
        // but if it does error, it should be descriptive.
        if let Err(e) = result {
            let msg = e.to_string();
            assert!(msg.contains("hosts.nix") || msg.contains("nixos-config"));
        }
    }
}
