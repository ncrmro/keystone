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

/// Extract nixosConfigurations attribute names and details from the flake AST.
fn extract_nixos_configurations(root: &SyntaxNode) -> Vec<HostInfo> {
    let mut hosts = Vec::new();

    // Walk the AST looking for nixosConfigurations
    for node in root.descendants() {
        if node.kind() == SyntaxKind::NODE_ATTRPATH_VALUE {
            // Check if this is nixosConfigurations = { ... }
            if let Some(attrpath) =
                node.children().find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)
            {
                let path_text: String = attrpath
                    .children()
                    .filter(|n| n.kind() == SyntaxKind::NODE_IDENT)
                    .map(|n| n.text().to_string())
                    .collect::<Vec<_>>()
                    .join(".");

                if path_text == "nixosConfigurations" {
                    // Found nixosConfigurations, now extract each host entry
                    if let Some(value) =
                        node.children().find(|n| n.kind() == SyntaxKind::NODE_ATTR_SET)
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
fn parse_host_entry(attr_node: &SyntaxNode) -> Option<HostInfo> {
    // Get the host name from the attrpath
    let key_path = attr_node
        .children()
        .find(|n| n.kind() == SyntaxKind::NODE_ATTRPATH)?;
    let name = key_path
        .children()
        .find(|n| n.kind() == SyntaxKind::NODE_IDENT)?
        .text()
        .to_string();

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
        assert!(hosts[0].config_files.contains(&"./configuration.nix".to_string()));
        assert!(hosts[0].config_files.contains(&"./hardware.nix".to_string()));
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
}
