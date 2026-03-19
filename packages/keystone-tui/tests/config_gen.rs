//! Tests for Nix configuration generation with authorized_keys.

use keystone_tui::template::{
    GenerateConfig, MachineType, RemoteUnlockConfig, StorageType, UserConfig,
};

#[test]
fn test_authorized_keys_appear_in_generated_nix() {
    let config = GenerateConfig {
        hostname: "test-server".to_string(),
        machine_type: MachineType::Server,
        storage_type: StorageType::Zfs,
        disk_device: Some("/dev/disk/by-id/nvme-test".to_string()),
        github_username: None,
        user: UserConfig {
            username: "admin".to_string(),
            password: "changeme".to_string(),
            authorized_keys: vec![
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA admin@laptop".to_string(),
                "ssh-rsa AAAAB3NzaC1yc2EAAAA admin@workstation".to_string(),
            ],
        },
        remote_unlock: RemoteUnlockConfig {
            enable: true,
            authorized_keys: vec!["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA admin@laptop".to_string()],
        },
    };

    let nix = keystone_tui::template::generate_configuration_nix(&config);

    // User authorized keys appear
    assert!(
        nix.contains("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA admin@laptop"),
        "User authorized_keys should contain the ed25519 key"
    );
    assert!(
        nix.contains("ssh-rsa AAAAB3NzaC1yc2EAAAA admin@workstation"),
        "User authorized_keys should contain the rsa key"
    );

    // authorizedKeys should be a proper Nix list (not empty)
    assert!(
        nix.contains("authorizedKeys = ["),
        "authorizedKeys should be a non-empty list"
    );

    // Remote unlock keys appear
    assert!(
        nix.matches("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA admin@laptop")
            .count()
            >= 2,
        "Key should appear in both user and remote unlock sections"
    );
}

#[test]
fn test_empty_authorized_keys_generates_empty_list() {
    let config = GenerateConfig {
        hostname: "empty-keys".to_string(),
        machine_type: MachineType::Laptop,
        storage_type: StorageType::Ext4,
        disk_device: Some("/dev/sda".to_string()),
        github_username: None,
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

    let nix = keystone_tui::template::generate_configuration_nix(&config);
    assert!(
        nix.contains("authorizedKeys = []"),
        "Empty keys should produce authorizedKeys = []"
    );
}

#[test]
fn test_flake_nix_contains_hostname() {
    let config = GenerateConfig {
        hostname: "my-server".to_string(),
        machine_type: MachineType::Server,
        storage_type: StorageType::Zfs,
        disk_device: Some("/dev/sda".to_string()),
        github_username: None,
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

    let flake = keystone_tui::template::generate_flake_nix(&config);
    assert!(flake.contains("\"my-server\" = nixpkgs.lib.nixosSystem"));
    assert!(flake.contains("keystone.nixosModules.operating-system"));
}

#[test]
fn test_laptop_gets_ext4_and_desktop() {
    let config = GenerateConfig {
        hostname: "my-laptop".to_string(),
        machine_type: MachineType::Laptop,
        storage_type: StorageType::Ext4,
        disk_device: Some("/dev/nvme0n1".to_string()),
        github_username: None,
        user: UserConfig {
            username: "user".to_string(),
            password: "pass".to_string(),
            authorized_keys: vec!["ssh-ed25519 AAAA key".to_string()],
        },
        remote_unlock: RemoteUnlockConfig {
            enable: false,
            authorized_keys: vec![],
        },
    };

    let configuration = keystone_tui::template::generate_configuration_nix(&config);
    assert!(configuration.contains(r#"type = "ext4""#));
    assert!(configuration.contains("desktop"));

    let flake = keystone_tui::template::generate_flake_nix(&config);
    // Desktop module should be enabled (not commented out)
    assert!(flake.contains("          keystone.nixosModules.desktop\n"));
}
