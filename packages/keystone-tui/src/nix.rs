//! Nix flake parsing and manipulation.

use anyhow::{Context, Result};
use rnix::{Root, SyntaxKind, SyntaxNode};
use std::path::Path;
use tokio::fs;

/// Information about a single NixOS host configuration.
#[derive(Debug, Clone)]
pub struct HostInfo {
    /// Host name (attribute key in nixosConfigurations).
    pub name: String,
    /// System architecture (e.g. "x86_64-linux"), parsed from `system = "..."`.
    pub system: Option<String>,
    /// Keystone modules imported (e.g. ["operating-system", "desktop"]).
    pub keystone_modules: Vec<String>,
    /// Local config file paths from the modules list (e.g. ["./configuration.nix"]).
    pub config_files: Vec<String>,
    /// Metadata from keystone.hosts (populated by eval_host_metadata).
    pub metadata: Option<HostMetadata>,
}

/// Metadata from keystone.hosts.<name> evaluated from the flake.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostMetadata {
    #[serde(default)]
    pub hostname: String,
    #[serde(default)]
    pub ssh_target: String,
    #[serde(default)]
    pub fallback_ip: String,
    #[serde(default)]
    pub role: String,
    #[serde(default)]
    pub baremetal: bool,
    #[serde(default)]
    pub zfs: bool,
    #[serde(default)]
    pub build_on_remote: bool,
}

/// Parsed information about a Keystone flake.
#[derive(Debug, Clone)]
pub struct FlakeInfo {
    /// List of NixOS host configurations defined in the flake.
    pub hosts: Vec<HostInfo>,
}

/// Parse a flake.nix file and extract configuration information.
pub async fn parse_flake(repo_path: &Path) -> Result<FlakeInfo> {
    let flake_path = repo_path.join("flake.nix");
    let content = fs::read_to_string(&flake_path)
        .await
        .context(format!("Failed to read {}", flake_path.display()))?;

    // Parse with rnix
    let root = Root::parse(&content);
    if !root.errors().is_empty() {
        let errors: Vec<_> = root.errors().iter().map(|e| e.to_string()).collect();
        anyhow::bail!("Failed to parse flake.nix: {}", errors.join(", "));
    }

    let syntax = root.syntax();
    let hosts = extract_nixos_configurations(&syntax);

    Ok(FlakeInfo { hosts })
}

/// Evaluate keystone.hosts metadata from the flake via `nix eval`.
///
/// Runs `nix eval .#nixosConfigurations.<host>.config.keystone.hosts --json`
/// and merges the results into the provided HostInfo entries. Hosts without
/// keystone.hosts entries are left with `metadata: None`.
///
/// This is a best-effort operation — if nix eval fails (e.g. no keystone.hosts
/// option), the hosts are returned unchanged.
pub async fn eval_host_metadata(repo_path: &Path, hosts: &mut [HostInfo]) {
    if hosts.is_empty() {
        return;
    }

    // Try evaluating keystone.hosts from the first host's config
    let first_host = &hosts[0].name;
    let expr = format!(
        "path:{}#nixosConfigurations.{}.config.keystone.hosts or {{}}",
        repo_path.display(),
        first_host,
    );

    let output = match tokio::process::Command::new("nix")
        .args(["eval", "--json", &expr])
        .current_dir(repo_path)
        .output()
        .await
    {
        Ok(o) if o.status.success() => o,
        _ => return, // nix eval failed — leave metadata as None
    };

    let json_str = String::from_utf8_lossy(&output.stdout);
    let parsed: std::collections::HashMap<String, HostMetadata> =
        match serde_json::from_str(&json_str) {
            Ok(v) => v,
            Err(_) => return,
        };

    for host in hosts.iter_mut() {
        if let Some(meta) = parsed.get(&host.name) {
            host.metadata = Some(meta.clone());
        }
    }
}

/// Extract nixosConfigurations attribute names and details from the flake AST.
fn extract_nixos_configurations(root: &SyntaxNode) -> Vec<HostInfo> {
    let mut hosts = Vec::new();

    // Walk the AST looking for nixosConfigurations
    for node in root.descendants() {
        if node.kind() == SyntaxKind::NODE_ATTRPATH_VALUE {
            // Check if this is nixosConfigurations = { ... }
            if let Some(attrpath) = node
                .children()
                .find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)
            {
                let path_text: String = attrpath
                    .children()
                    .filter(|n| n.kind() == SyntaxKind::NODE_IDENT)
                    .map(|n| n.text().to_string())
                    .collect::<Vec<_>>()
                    .join(".");

                if path_text == "nixosConfigurations" {
                    // Found nixosConfigurations, now extract each host entry
                    if let Some(value) = node
                        .children()
                        .find(|n| n.kind() == SyntaxKind::NODE_ATTR_SET)
                    {
                        for attr in value.children() {
                            if attr.kind() == SyntaxKind::NODE_ATTRPATH_VALUE {
                                if let Some(host_info) = parse_host_entry(&attr) {
                                    hosts.push(host_info);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    hosts
}

/// Parse a single host entry from the nixosConfigurations attrset.
/// Expects a node like: `my-machine = nixpkgs.lib.nixosSystem { system = "..."; modules = [...]; };`
/// Also handles quoted keys like: `"my-machine" = nixpkgs.lib.nixosSystem { ... };`
fn parse_host_entry(attr_node: &SyntaxNode) -> Option<HostInfo> {
    // Get the host name from the attrpath — may be NODE_IDENT (bare) or NODE_STRING (quoted)
    let key_path = attr_node
        .children()
        .find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)?;
    let name = key_path
        .children()
        .find_map(|n| match n.kind() {
            SyntaxKind::NODE_IDENT => Some(n.text().to_string()),
            SyntaxKind::NODE_STRING => {
                let text = n.text().to_string();
                Some(text.trim_matches('"').to_string())
            }
            _ => None,
        })?;

    // Find the value node - it should be a function application like `nixpkgs.lib.nixosSystem { ... }`
    // The attrset argument is what we need to inspect
    let mut system = None;
    let mut keystone_modules = Vec::new();
    let mut config_files = Vec::new();

    // Look for NODE_APPLY (function application) which contains the attrset argument
    for descendant in attr_node.descendants() {
        if descendant.kind() == SyntaxKind::NODE_ATTR_SET {
            // Check children of this attrset for `system` and `modules`
            for child in descendant.children() {
                if child.kind() == SyntaxKind::NODE_ATTRPATH_VALUE {
                    if let Some(ap) = child
                        .children()
                        .find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)
                    {
                        let attr_name: String = ap
                            .children()
                            .filter(|n| n.kind() == SyntaxKind::NODE_IDENT)
                            .map(|n| n.text().to_string())
                            .collect::<Vec<_>>()
                            .join(".");

                        match attr_name.as_str() {
                            "system" => {
                                system = extract_string_value(&child);
                            }
                            "modules" => {
                                // Parse the modules list
                                if let Some(list_node) = child
                                    .descendants()
                                    .find(|n| n.kind() == SyntaxKind::NODE_LIST)
                                {
                                    parse_modules_list(
                                        &list_node,
                                        &mut keystone_modules,
                                        &mut config_files,
                                    );
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }
            // Only parse the first (outermost) attrset for this host entry
            break;
        }
    }

    Some(HostInfo {
        name,
        system,
        keystone_modules,
        config_files,
        metadata: None,
    })
}

/// Extract a string literal value from an attrpath_value node.
/// e.g., for `system = "x86_64-linux";`, returns Some("x86_64-linux").
fn extract_string_value(attr_node: &SyntaxNode) -> Option<String> {
    for descendant in attr_node.descendants() {
        if descendant.kind() == SyntaxKind::NODE_STRING {
            // Get the string content (the parts between quotes)
            let text = descendant.text().to_string();
            // Strip surrounding quotes
            let trimmed = text.trim_matches('"');
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    None
}

/// Parse a modules list and extract keystone module names and config file paths.
fn parse_modules_list(
    list_node: &SyntaxNode,
    keystone_modules: &mut Vec<String>,
    config_files: &mut Vec<String>,
) {
    for child in list_node.children() {
        let text = child.text().to_string();

        // Check for keystone.nixosModules.X or keystone.homeModules.X
        if text.contains("keystone.nixosModules.") {
            if let Some(module_name) = text.split("keystone.nixosModules.").nth(1) {
                let module_name = module_name.trim();
                if !module_name.is_empty() {
                    keystone_modules.push(module_name.to_string());
                }
            }
        }

        // Check for local config file paths like ./configuration.nix
        if child.kind() == SyntaxKind::NODE_PATH {
            let path_text = text.trim().to_string();
            if path_text.ends_with(".nix") {
                config_files.push(path_text);
            }
        }
    }
}

/// A single flake input parsed from `inputs = { ... }`.
#[derive(Debug, Clone)]
pub struct FlakeInputInfo {
    /// Input name (e.g. "nixpkgs", "keystone", "disko").
    pub name: String,
    /// URL if specified (e.g. "github:NixOS/nixpkgs/nixos-unstable").
    pub url: Option<String>,
    /// Names of inputs this one follows (e.g. "nixpkgs" from `inputs.nixpkgs.follows`).
    pub follows: Vec<String>,
}

/// Extract flake inputs from a parsed Nix expression.
/// Works on the raw string content (parses internally).
pub fn extract_flake_inputs(content: &str) -> Vec<FlakeInputInfo> {
    let root = Root::parse(content);
    let syntax = root.syntax();
    extract_inputs_from_ast(&syntax)
}

/// Walk the AST looking for `inputs = { ... }` and extract each input entry.
fn extract_inputs_from_ast(root: &SyntaxNode) -> Vec<FlakeInputInfo> {
    let mut inputs = Vec::new();

    for node in root.descendants() {
        if node.kind() == SyntaxKind::NODE_ATTRPATH_VALUE {
            if let Some(attrpath) = node
                .children()
                .find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)
            {
                let path_text: String = attrpath
                    .children()
                    .filter(|n| n.kind() == SyntaxKind::NODE_IDENT)
                    .map(|n| n.text().to_string())
                    .collect::<Vec<_>>()
                    .join(".");

                if path_text == "inputs" {
                    if let Some(value) = node
                        .children()
                        .find(|n| n.kind() == SyntaxKind::NODE_ATTR_SET)
                    {
                        for attr in value.children() {
                            if attr.kind() == SyntaxKind::NODE_ATTRPATH_VALUE {
                                if let Some(input) = parse_input_entry(&attr) {
                                    inputs.push(input);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    inputs
}

/// Parse a single input entry from the inputs attrset.
fn parse_input_entry(attr_node: &SyntaxNode) -> Option<FlakeInputInfo> {
    let key_path = attr_node
        .children()
        .find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)?;

    let idents: Vec<String> = key_path
        .children()
        .filter(|n| n.kind() == SyntaxKind::NODE_IDENT)
        .map(|n| n.text().to_string())
        .collect();

    // Handle both `nixpkgs.url = "..."` (dotted) and `nixpkgs = { url = "..."; }` (nested)
    let name = idents.first()?.to_string();

    // Dotted style: `nixpkgs.url = "..."` — the name is the first ident, value is the url
    if idents.len() == 2 && idents[1] == "url" {
        let url = extract_string_value(attr_node);
        return Some(FlakeInputInfo {
            name,
            url,
            follows: vec![],
        });
    }

    // Nested attrset style: `nixpkgs = { url = "..."; inputs.X.follows = "Y"; }`
    let mut url = None;
    let mut follows = Vec::new();

    // Check if value is a string (shorthand: `nixpkgs.url = "..."`)
    if idents.len() == 1 {
        // Look for nested attrset
        for descendant in attr_node.children() {
            if descendant.kind() == SyntaxKind::NODE_ATTR_SET {
                for child in descendant.children() {
                    if child.kind() == SyntaxKind::NODE_ATTRPATH_VALUE {
                        let child_path: String = child
                            .descendants()
                            .filter(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)
                            .flat_map(|n| {
                                n.children()
                                    .filter(|c| c.kind() == SyntaxKind::NODE_IDENT)
                                    .map(|c| c.text().to_string())
                            })
                            .collect::<Vec<_>>()
                            .join(".");

                        if child_path == "url" {
                            url = extract_string_value(&child);
                        } else if child_path.ends_with(".follows") {
                            if let Some(val) = extract_string_value(&child) {
                                follows.push(val);
                            }
                        }
                    }
                }
            }
            // Also handle plain string value: `nixpkgs.url = "..."`
            if descendant.kind() == SyntaxKind::NODE_STRING {
                let text = descendant.text().to_string();
                let trimmed = text.trim_matches('"');
                if !trimmed.is_empty() {
                    url = Some(trimmed.to_string());
                }
            }
        }
    }

    Some(FlakeInputInfo {
        name,
        url,
        follows,
    })
}

/// Extract the names of modules in a host's `modules = [...]` list from a flake string.
/// This is a convenience wrapper for testing generated flakes.
pub fn extract_nixos_configurations_from_str(content: &str) -> Vec<HostInfo> {
    let root = Root::parse(content);
    extract_nixos_configurations(&root.syntax())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_hosts() {
        let content = r#"
{
  outputs = { nixpkgs, ... }: {
    nixosConfigurations = {
      myhost = nixpkgs.lib.nixosSystem { };
      another-host = nixpkgs.lib.nixosSystem { };
    };
  };
}
"#;
        let root = Root::parse(content);
        let hosts = extract_nixos_configurations(&root.syntax());
        assert_eq!(hosts.len(), 2);
        assert_eq!(hosts[0].name, "myhost");
        assert_eq!(hosts[1].name, "another-host");
    }

    #[test]
    fn test_extract_system() {
        let content = r#"
{
  outputs = { nixpkgs, ... }: {
    nixosConfigurations = {
      myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [];
      };
    };
  };
}
"#;
        let root = Root::parse(content);
        let hosts = extract_nixos_configurations(&root.syntax());
        assert_eq!(hosts.len(), 1);
        assert_eq!(hosts[0].name, "myhost");
        assert_eq!(hosts[0].system.as_deref(), Some("x86_64-linux"));
    }

    #[test]
    fn test_extract_keystone_modules() {
        let content = r#"
{
  outputs = { nixpkgs, keystone, ... }: {
    nixosConfigurations = {
      myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          keystone.nixosModules.operating-system
          keystone.nixosModules.desktop
          ./configuration.nix
          ./hardware.nix
        ];
      };
    };
  };
}
"#;
        let root = Root::parse(content);
        let hosts = extract_nixos_configurations(&root.syntax());
        assert_eq!(hosts.len(), 1);
        assert_eq!(
            hosts[0].keystone_modules,
            vec!["operating-system", "desktop"]
        );
        assert_eq!(
            hosts[0].config_files,
            vec!["./configuration.nix", "./hardware.nix"]
        );
    }

    #[test]
    fn test_template_flake() {
        let content = r#"
{
  outputs = { self, nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations = {
      my-machine = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          keystone.nixosModules.operating-system
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              sharedModules = [
                keystone.homeModules.terminal
                keystone.homeModules.desktop
              ];
            };
          }
          ./configuration.nix
          ./hardware.nix
        ];
      };
    };
  };
}
"#;
        let root = Root::parse(content);
        let hosts = extract_nixos_configurations(&root.syntax());
        assert_eq!(hosts.len(), 1);
        assert_eq!(hosts[0].name, "my-machine");
        assert_eq!(hosts[0].system.as_deref(), Some("x86_64-linux"));
        assert_eq!(hosts[0].keystone_modules, vec!["operating-system"]);
        assert!(hosts[0]
            .config_files
            .contains(&"./configuration.nix".to_string()));
        assert!(hosts[0]
            .config_files
            .contains(&"./hardware.nix".to_string()));
    }

    #[test]
    fn test_multiple_hosts_different_configs() {
        let content = r#"
{
  outputs = { nixpkgs, keystone, ... }: {
    nixosConfigurations = {
      server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          keystone.nixosModules.operating-system
          ./server.nix
        ];
      };
      workstation = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          keystone.nixosModules.operating-system
          keystone.nixosModules.desktop
          keystone.nixosModules.agent
          ./workstation.nix
        ];
      };
    };
  };
}
"#;
        let root = Root::parse(content);
        let hosts = extract_nixos_configurations(&root.syntax());
        assert_eq!(hosts.len(), 2);

        assert_eq!(hosts[0].name, "server");
        assert_eq!(hosts[0].keystone_modules, vec!["operating-system"]);
        assert_eq!(hosts[0].config_files, vec!["./server.nix"]);

        assert_eq!(hosts[1].name, "workstation");
        assert_eq!(
            hosts[1].keystone_modules,
            vec!["operating-system", "desktop", "agent"]
        );
        assert_eq!(hosts[1].config_files, vec!["./workstation.nix"]);
    }

    #[test]
    fn test_extract_flake_inputs_nested_style() {
        let content = r#"
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    keystone = {
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { ... }: {};
}
"#;
        let inputs = extract_flake_inputs(content);
        let names: Vec<&str> = inputs.iter().map(|i| i.name.as_str()).collect();
        assert!(names.contains(&"nixpkgs"), "should find nixpkgs input");
        assert!(names.contains(&"keystone"), "should find keystone input");
        assert!(names.contains(&"disko"), "should find disko input");
        assert!(names.contains(&"home-manager"), "should find home-manager input");

        let disko = inputs.iter().find(|i| i.name == "disko").unwrap();
        assert_eq!(
            disko.url.as_deref(),
            Some("github:nix-community/disko")
        );
        assert!(disko.follows.contains(&"nixpkgs".to_string()));
    }

    #[test]
    fn test_extract_flake_inputs_dotted_style() {
        let content = r#"
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { ... }: {};
}
"#;
        let inputs = extract_flake_inputs(content);
        assert_eq!(inputs.len(), 1);
        assert_eq!(inputs[0].name, "nixpkgs");
        assert_eq!(
            inputs[0].url.as_deref(),
            Some("github:NixOS/nixpkgs/nixos-unstable")
        );
    }

    #[test]
    fn test_extract_configurations_from_generated_flake() {
        // Use the actual template generator to prove round-trip correctness
        use crate::template::*;

        let config = GenerateConfig {
            hostname: "ast-test".to_string(),
            machine_type: MachineType::Server,
            storage_type: StorageType::Zfs,
            disk_device: None,
            github_username: None,
            time_zone: "UTC".to_string(),
            state_version: "25.05".to_string(),
            user: UserConfig {
                username: "admin".to_string(),
                password: "pass".to_string(),
                authorized_keys: vec![],
            },
            remote_unlock: RemoteUnlockConfig {
                enable: false,
                authorized_keys: vec![],
            },
        };

        let flake = generate_flake_nix(&config);

        // Verify inputs via AST
        let inputs = extract_flake_inputs(&flake);
        let input_names: Vec<&str> = inputs.iter().map(|i| i.name.as_str()).collect();
        assert!(input_names.contains(&"disko"), "generated flake must have disko input");
        assert!(input_names.contains(&"keystone"), "generated flake must have keystone input");
        assert!(input_names.contains(&"home-manager"), "generated flake must have home-manager input");

        // Verify the flake parses without errors
        let root = Root::parse(&flake);
        let errors: Vec<_> = root.errors().iter().map(|e| e.to_string()).collect();
        assert!(errors.is_empty(), "generated flake has parse errors: {:?}", errors);

        // Verify host via AST
        let hosts = extract_nixos_configurations_from_str(&flake);
        assert_eq!(hosts.len(), 1);
        assert_eq!(hosts[0].name, "ast-test");
        assert_eq!(hosts[0].system.as_deref(), Some("x86_64-linux"));
        assert!(hosts[0].keystone_modules.contains(&"operating-system".to_string()));
    }
}
