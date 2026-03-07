use crate::config::TemplateConfig;

pub fn generate_flake_nix(config: &TemplateConfig) -> String {
    let mut has_desktop = false;
    let mut has_hm = false;

    for user in config.users.values() {
        if let Some(desktop) = &user.desktop {
            if desktop.enable {
                has_desktop = true;
                has_hm = true;
            }
        }
        if user.terminal.unwrap_or(true) {
            has_hm = true;
        }
    }

    let mut modules = vec![
        "keystone.nixosModules.operating-system".to_string(),
        "./configuration.nix".to_string(),
    ];

    if has_hm {
        modules.insert(0, "home-manager.nixosModules.home-manager".to_string());
    }

    if has_desktop {
        modules.insert(1, "keystone.nixosModules.desktop".to_string());
    }

    let modules_str = modules
        .iter()
        .map(|m| format!("          {}", m))
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r#"{{
  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    keystone.url = "github:ncrmro/keystone";
    keystone.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  }};

  outputs = {{ nixpkgs, keystone, home-manager, ... }}: {{
    nixosConfigurations.{} = nixpkgs.lib.nixosSystem {{
      system = "x86_64-linux";
      modules = [
{}
      ];
    }};
  }};
}}
"#,
        config.hostname, modules_str
    )
}

pub fn generate_configuration_nix(config: &TemplateConfig) -> String {
    use crate::config::{StorageType, UserAuth};

    let mut content = format!(
        r#"{{
  imports = [ ./hardware.nix ];

  networking.hostName = "{}";
  networking.hostId = "{}";
  system.stateVersion = "{}";
  time.timeZone = "{}";

  keystone.os = {{
    enable = true;
    storage = {{
      type = "{}";
      devices = [ {} ];
"#,
        config.hostname,
        config.host_id,
        config.state_version,
        config.time_zone.as_deref().unwrap_or("UTC"),
        match config.storage.storage_type {
            StorageType::Zfs => "zfs",
            StorageType::Ext4 => "ext4",
        },
        config
            .storage
            .devices
            .iter()
            .map(|d| format!("\"{}\"", d))
            .collect::<Vec<_>>()
            .join(" ")
    );

    if let Some(mode) = &config.storage.mode {
        content.push_str(&format!("      mode = \"{:?}\";\n", mode).to_lowercase());
    }

    if let Some(swap_size) = &config.storage.swap_size {
        content.push_str(&format!("      swap.size = \"{}\";\n", swap_size));
    }

    if let Some(hibernate) = config.storage.hibernate {
        content.push_str(&format!("      hibernate.enable = {};\n", hibernate));
    }

    content.push_str("    };\n");

    if let Some(sb) = config.secure_boot {
        content.push_str(&format!("    secureBoot.enable = {};\n", sb));
    }

    if let Some(tpm) = config.tpm {
        content.push_str(&format!("    tpm.enable = {};\n", tpm));
    }

    if let Some(ru) = &config.remote_unlock {
        content.push_str("    remoteUnlock = {\n");
        content.push_str(&format!("      enable = {};\n", ru.enable));
        if !ru.authorized_keys.is_empty() {
            content.push_str(&format!(
                "      authorizedKeys = [ {} ];\n",
                ru.authorized_keys
                    .iter()
                    .map(|k| format!("\"{}\"", k))
                    .collect::<Vec<_>>()
                    .join(" ")
            ));
        }
        content.push_str("    };\n");
    }

    content.push_str("    users = {\n");
    for (username, user) in &config.users {
        content.push_str(&format!("      {} = {{\n", username));
        content.push_str(&format!("        fullName = \"{}\";\n", user.full_name));
        if let Some(email) = &user.email {
            content.push_str(&format!("        email = \"{}\";\n", email));
        }

        match &user.auth {
            UserAuth::InitialPassword(p) => {
                content.push_str(&format!("        initialPassword = \"{}\";\n", p))
            }
            UserAuth::HashedPassword(p) => {
                content.push_str(&format!("        hashedPassword = \"{}\";\n", p))
            }
        }

        if !user.authorized_keys.is_empty() {
            content.push_str(&format!(
                "        authorizedKeys = [ {} ];\n",
                user.authorized_keys
                    .iter()
                    .map(|k| format!("\"{}\"", k))
                    .collect::<Vec<_>>()
                    .join(" ")
            ));
        }

        if !user.extra_groups.is_empty() {
            content.push_str(&format!(
                "        extraGroups = [ {} ];\n",
                user.extra_groups
                    .iter()
                    .map(|g| format!("\"{}\"", g))
                    .collect::<Vec<_>>()
                    .join(" ")
            ));
        }

        if let Some(terminal) = user.terminal {
            content.push_str(&format!("        terminal.enable = {};\n", terminal));
        }

        if let Some(desktop) = &user.desktop {
            content.push_str("        desktop = {\n");
            content.push_str(&format!("          enable = {};\n", desktop.enable));
            if let Some(hyprland) = &desktop.hyprland {
                content.push_str("          hyprland = {\n");
                content.push_str(&format!(
                    "            modifierKey = \"{}\";\n",
                    hyprland.modifier_key
                ));
                content.push_str("          };\n");
            }
            content.push_str("        };\n");
        }

        content.push_str("      };\n");
    }

    content.push_str("    };\n");
    content.push_str("  };\n");
    content.push_str("}\n");

    content
}

pub fn generate_hardware_nix(_config: &TemplateConfig) -> String {
    "{ ... }: { }\n".to_string()
}
