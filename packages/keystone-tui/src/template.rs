//! Nix configuration template generation.
//!
//! Generates flake.nix, configuration.nix, and hardware.nix from
//! user-provided configuration parameters.

/// Machine type determines which Keystone modules are included.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MachineType {
    Server,
    Workstation,
    Laptop,
}

impl MachineType {
    pub fn label(&self) -> &'static str {
        match self {
            MachineType::Server => "Server (headless)",
            MachineType::Workstation => "Workstation (desktop + ZFS)",
            MachineType::Laptop => "Laptop (desktop + ext4 + hibernate)",
        }
    }
}

/// Storage backend type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StorageType {
    Zfs,
    Ext4,
}

impl StorageType {
    pub fn label(&self) -> &'static str {
        match self {
            StorageType::Zfs => "ZFS (snapshots, compression)",
            StorageType::Ext4 => "ext4 (simple, hibernation-compatible)",
        }
    }

    pub fn nix_value(&self) -> &'static str {
        match self {
            StorageType::Zfs => "zfs",
            StorageType::Ext4 => "ext4",
        }
    }
}

/// User configuration for a Keystone machine.
pub struct UserConfig {
    pub username: String,
    pub password: String,
    pub authorized_keys: Vec<String>,
}

/// Remote unlock configuration.
pub struct RemoteUnlockConfig {
    pub enable: bool,
    pub authorized_keys: Vec<String>,
}

/// Full configuration for generating Nix files.
pub struct GenerateConfig {
    pub hostname: String,
    pub machine_type: MachineType,
    pub storage_type: StorageType,
    pub disk_device: String,
    pub user: UserConfig,
    pub remote_unlock: RemoteUnlockConfig,
}

/// Generate a flake.nix file from configuration.
pub fn generate_flake_nix(config: &GenerateConfig) -> String {
    let desktop_module = match config.machine_type {
        MachineType::Server => "          # keystone.nixosModules.desktop  # Uncomment for desktop",
        _ => "          keystone.nixosModules.desktop",
    };

    // The desktop home module already imports terminal, so only include
    // terminal separately for server configs (no desktop).
    let shared_modules = match config.machine_type {
        MachineType::Server => concat!(
            "              sharedModules = [\n",
            "                keystone.homeModules.terminal\n",
            "              ];",
        ),
        // Desktop home module already imports terminal internally;
        // including both would cause a duplicate option declaration.
        _ => concat!(
            "              sharedModules = [\n",
            "                keystone.homeModules.desktop\n",
            "              ];",
        ),
    };

    format!(
        r#"{{
  description = "Keystone Infrastructure — {hostname}";

  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    keystone = {{
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
    home-manager = {{
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
  }};

  outputs = {{
    self,
    nixpkgs,
    keystone,
    home-manager,
    ...
  }}: {{
    nixosConfigurations = {{
      {hostname} = nixpkgs.lib.nixosSystem {{
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          keystone.nixosModules.operating-system
{desktop_module}
          {{
            nixpkgs.overlays = [ keystone.overlays.default ];
            home-manager = {{
              useGlobalPkgs = true;
              useUserPackages = true;
{shared_modules}
            }};
          }}
          ./configuration.nix
          ./hardware.nix
        ];
      }};
    }};

    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {{
      packages = with nixpkgs.legacyPackages.x86_64-linux; [
        nixfmt-rfc-style
        nil
      ];
    }};
  }};
}}
"#,
        hostname = config.hostname,
        desktop_module = desktop_module,
        shared_modules = shared_modules,
    )
}

/// Generate a configuration.nix file from configuration.
pub fn generate_configuration_nix(config: &GenerateConfig) -> String {
    let host_id = generate_host_id();

    let authorized_keys_nix = format_nix_string_list(&config.user.authorized_keys, 10);
    let remote_unlock_keys_nix =
        format_nix_string_list(&config.remote_unlock.authorized_keys, 8);

    let desktop_enable = match config.machine_type {
        MachineType::Server => "false",
        _ => "true",
    };

    let remote_unlock_enable = match config.machine_type {
        MachineType::Server => "true",
        _ => "false",
    };

    let extra_groups = match config.machine_type {
        MachineType::Server => r#"[ "wheel" ]"#,
        _ => r#"[ "wheel" "networkmanager" "video" "audio" ]"#,
    };

    format!(
        r#"{{
  config,
  pkgs,
  lib,
  ...
}}: {{
  networking.hostName = "{hostname}";
  networking.hostId = "{host_id}";
  system.stateVersion = "25.05";

  keystone.os = {{
    enable = true;

    storage = {{
      type = "{storage_type}";
      devices = [
        "{disk_device}"
      ];
      mode = "single";
      swap.size = "16G";
    }};

    secureBoot.enable = true;
    tpm = {{
      enable = true;
      pcrs = [ 1 7 ];
    }};
    ssh.enable = true;

    remoteUnlock = {{
      enable = {remote_unlock_enable};
      port = 22;
      dhcp = true;
      networkModule = "virtio_net";
      authorizedKeys = {remote_unlock_keys_nix};
    }};

    users = {{
      {username} = {{
        fullName = "{username}";
        email = "{username}@localhost";
        extraGroups = {extra_groups};
        initialPassword = "{password}";
        authorizedKeys = {authorized_keys_nix};
        terminal.enable = true;
        desktop = {{
          enable = {desktop_enable};
          hyprland = {{
            modifierKey = "SUPER";
            capslockAsControl = true;
          }};
        }};
      }};
    }};
  }};

  time.timeZone = "UTC";
  nix.settings.trusted-users = [ "root" "@wheel" ];
  environment.systemPackages = with pkgs; [ sbctl ];
}}
"#,
        hostname = config.hostname,
        host_id = host_id,
        storage_type = config.storage_type.nix_value(),
        disk_device = config.disk_device,
        username = config.user.username,
        password = config.user.password,
        authorized_keys_nix = authorized_keys_nix,
        remote_unlock_enable = remote_unlock_enable,
        remote_unlock_keys_nix = remote_unlock_keys_nix,
        extra_groups = extra_groups,
        desktop_enable = desktop_enable,
    )
}

/// Generate a flake.nix for a pre-baked installer ISO.
///
/// The ISO embeds the user's generated config files (flake.nix, configuration.nix,
/// hardware.nix) at `/etc/keystone/install-config/` so the TUI installer on the
/// target machine can run disko + nixos-install without needing the config repo.
pub fn generate_iso_flake_nix(config: &GenerateConfig) -> String {
    let ssh_keys_nix = format_nix_string_list(&config.user.authorized_keys, 12);

    format!(
        r#"{{
  description = "Keystone Installer ISO — {hostname}";

  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    keystone = {{
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
    home-manager = {{
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
  }};

  outputs = {{
    self,
    nixpkgs,
    keystone,
    home-manager,
    ...
  }}: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${{system}};
  in {{
    nixosConfigurations.keystoneIso = nixpkgs.lib.nixosSystem {{
      inherit system;
      modules = [
        "${{nixpkgs}}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        keystone.nixosModules.isoInstaller
        {{
          # SSH keys for remote access during installation
          keystone.installer.sshKeys = {ssh_keys_nix};

          # Embed the user's NixOS config files into the ISO filesystem.
          # The TUI installer reads these from /etc/keystone/install-config/
          # to run disko + nixos-install on the target machine.
          environment.etc."keystone/install-config/flake.nix".source = ./target-config/flake.nix;
          environment.etc."keystone/install-config/configuration.nix".source = ./target-config/configuration.nix;
          environment.etc."keystone/install-config/hardware.nix".source = ./target-config/hardware.nix;
          environment.etc."keystone/install-config/hostname".text = "{hostname}";

          # Pin kernel to match upstream keystone ISO (6.12)
          boot.kernelPackages = nixpkgs.lib.mkForce pkgs.linuxPackages_6_12;
        }}
      ];
    }};
  }};
}}
"#,
        hostname = config.hostname,
        ssh_keys_nix = ssh_keys_nix,
    )
}

/// Generate a minimal hardware.nix placeholder.
pub fn generate_hardware_nix() -> String {
    r#"{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Hardware configuration will be populated by nixos-generate-config
  # after installation, or by nixos-anywhere during deployment.
}
"#
    .to_string()
}

/// Generate a random 8-character hex host ID.
fn generate_host_id() -> String {
    use std::io::Read;
    let mut buf = [0u8; 4];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut buf);
    }
    // Fallback: use a simple hash of the current time
    if buf == [0u8; 4] {
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        buf = (t as u32).to_le_bytes();
    }
    format!("{:02x}{:02x}{:02x}{:02x}", buf[0], buf[1], buf[2], buf[3])
}

/// Format a Vec<String> as a Nix list of strings with proper indentation.
fn format_nix_string_list(items: &[String], indent: usize) -> String {
    if items.is_empty() {
        return "[]".to_string();
    }
    let pad = " ".repeat(indent);
    let mut result = String::from("[\n");
    for item in items {
        result.push_str(&format!("{}  \"{}\"\n", pad, item));
    }
    result.push_str(&format!("{}]", pad));
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_nix_string_list_empty() {
        assert_eq!(format_nix_string_list(&[], 0), "[]");
    }

    #[test]
    fn test_format_nix_string_list_with_keys() {
        let keys = vec![
            "ssh-ed25519 AAAAC3test key1".to_string(),
            "ssh-ed25519 AAAAC3test key2".to_string(),
        ];
        let result = format_nix_string_list(&keys, 8);
        assert!(result.contains("\"ssh-ed25519 AAAAC3test key1\""));
        assert!(result.contains("\"ssh-ed25519 AAAAC3test key2\""));
        assert!(result.starts_with('['));
        assert!(result.ends_with(']'));
    }

    #[test]
    fn test_generate_configuration_with_authorized_keys() {
        let config = GenerateConfig {
            hostname: "test-host".to_string(),
            machine_type: MachineType::Server,
            storage_type: StorageType::Zfs,
            disk_device: "/dev/disk/by-id/test-disk".to_string(),
            user: UserConfig {
                username: "admin".to_string(),
                password: "changeme".to_string(),
                authorized_keys: vec![
                    "ssh-ed25519 AAAAC3testkey admin@laptop".to_string(),
                ],
            },
            remote_unlock: RemoteUnlockConfig {
                enable: true,
                authorized_keys: vec![
                    "ssh-ed25519 AAAAC3testkey admin@laptop".to_string(),
                ],
            },
        };

        let nix = generate_configuration_nix(&config);
        assert!(nix.contains("test-host"));
        assert!(nix.contains(r#"type = "zfs""#));
        assert!(nix.contains("ssh-ed25519 AAAAC3testkey admin@laptop"));
        assert!(nix.contains(r#"enable = true"#));
    }

    #[test]
    fn test_generate_configuration_without_keys() {
        let config = GenerateConfig {
            hostname: "my-laptop".to_string(),
            machine_type: MachineType::Laptop,
            storage_type: StorageType::Ext4,
            disk_device: "/dev/disk/by-id/nvme-test".to_string(),
            user: UserConfig {
                username: "user".to_string(),
                password: "pass".to_string(),
                authorized_keys: vec![],
            },
            remote_unlock: RemoteUnlockConfig {
                enable: false,
                authorized_keys: vec![],
            },
        };

        let nix = generate_configuration_nix(&config);
        assert!(nix.contains("my-laptop"));
        assert!(nix.contains(r#"type = "ext4""#));
        assert!(nix.contains("authorizedKeys = []"));
    }

    #[test]
    fn test_generate_flake_server() {
        let config = GenerateConfig {
            hostname: "server1".to_string(),
            machine_type: MachineType::Server,
            storage_type: StorageType::Zfs,
            disk_device: "test".to_string(),
            user: UserConfig {
                username: "admin".to_string(),
                password: "pass".to_string(),
                authorized_keys: vec![],
            },
            remote_unlock: RemoteUnlockConfig {
                enable: true,
                authorized_keys: vec![],
            },
        };

        let flake = generate_flake_nix(&config);
        assert!(flake.contains("server1"));
        assert!(flake.contains("# keystone.nixosModules.desktop"));
    }

    #[test]
    fn test_generate_flake_workstation() {
        let config = GenerateConfig {
            hostname: "workstation".to_string(),
            machine_type: MachineType::Workstation,
            storage_type: StorageType::Zfs,
            disk_device: "test".to_string(),
            user: UserConfig {
                username: "dev".to_string(),
                password: "pass".to_string(),
                authorized_keys: vec![],
            },
            remote_unlock: RemoteUnlockConfig {
                enable: false,
                authorized_keys: vec![],
            },
        };

        let flake = generate_flake_nix(&config);
        assert!(flake.contains("workstation"));
        // Desktop module should NOT be commented out for workstation
        assert!(flake.contains("          keystone.nixosModules.desktop\n"));
    }

    #[test]
    fn test_generate_host_id_format() {
        let id = generate_host_id();
        assert_eq!(id.len(), 8);
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_generate_iso_flake_contains_hostname() {
        let config = GenerateConfig {
            hostname: "my-laptop".to_string(),
            machine_type: MachineType::Laptop,
            storage_type: StorageType::Ext4,
            disk_device: "/dev/disk/by-id/nvme-test".to_string(),
            user: UserConfig {
                username: "user".to_string(),
                password: "pass".to_string(),
                authorized_keys: vec![],
            },
            remote_unlock: RemoteUnlockConfig {
                enable: false,
                authorized_keys: vec![],
            },
        };

        let iso_flake = generate_iso_flake_nix(&config);
        assert!(iso_flake.contains("my-laptop"));
        assert!(iso_flake.contains("keystoneIso"));
        assert!(iso_flake.contains("keystone/install-config/flake.nix"));
        assert!(iso_flake.contains("keystone/install-config/configuration.nix"));
        assert!(iso_flake.contains("keystone/install-config/hardware.nix"));
        assert!(iso_flake.contains("isoInstaller"));
        assert!(iso_flake.contains("target-config/flake.nix"));
    }
}
