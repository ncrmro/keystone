use keystone_tui::config::{
    DesktopConfig, StorageConfig, StorageMode, StorageType, TemplateConfig, UserAuth, UserConfig,
};
use keystone_tui::generator::{
    generate_configuration_nix, generate_flake_nix, generate_hardware_nix,
};
use rnix::Root;
use std::collections::HashMap;

fn create_minimal_zfs_config() -> TemplateConfig {
    let mut users = HashMap::new();
    users.insert(
        "testuser".to_string(),
        UserConfig {
            full_name: "Test User".to_string(),
            email: Some("test@example.com".to_string()),
            auth: UserAuth::InitialPassword("password".to_string()),
            authorized_keys: vec![],
            extra_groups: vec!["wheel".to_string()],
            terminal: Some(true),
            desktop: None,
        },
    );

    TemplateConfig {
        hostname: "test-host".to_string(),
        host_id: "deadbeef".to_string(),
        state_version: "24.11".to_string(),
        time_zone: Some("UTC".to_string()),
        storage: StorageConfig {
            storage_type: StorageType::Zfs,
            devices: vec!["/dev/disk/by-id/disk1".to_string()],
            mode: Some(StorageMode::Single),
            swap_size: Some("16G".to_string()),
            hibernate: None,
        },
        secure_boot: Some(true),
        tpm: Some(true),
        remote_unlock: None,
        users,
    }
}

fn create_mirror_zfs_config() -> TemplateConfig {
    let mut config = create_minimal_zfs_config();
    config.storage.devices.push("/dev/disk/by-id/disk2".to_string());
    config.storage.mode = Some(StorageMode::Mirror);
    config
}

fn create_ext4_simple_config() -> TemplateConfig {
    let mut config = create_minimal_zfs_config();
    config.storage.storage_type = StorageType::Ext4;
    config
}

fn create_zfs_desktop_config() -> TemplateConfig {
    let mut config = create_minimal_zfs_config();
    if let Some(user) = config.users.get_mut("testuser") {
        user.desktop = Some(DesktopConfig {
            enable: true,
            hyprland: None,
        });
    }
    config
}

fn validate_nix_syntax(content: &str) {
    let parse = Root::parse(content);
    let errors: Vec<_> = parse.errors().into_iter().collect();
    assert!(
        errors.is_empty(),
        "Nix syntax errors: {:?}\nContent:\n{}",
        errors,
        content
    );
}

fn assert_no_todo(content: &str) {
    assert!(!content.contains("TODO:"), "Content contains TODO markers");
}

#[test]
fn test_minimal_zfs_generation() {
    let config = create_minimal_zfs_config();
    let flake = generate_flake_nix(&config);
    let configuration = generate_configuration_nix(&config);
    let hardware = generate_hardware_nix(&config);

    validate_nix_syntax(&flake);
    validate_nix_syntax(&configuration);
    validate_nix_syntax(&hardware);

    assert_no_todo(&flake);
    assert_no_todo(&configuration);
    assert_no_todo(&hardware);

    assert!(flake.contains("nixpkgs.url"));
    assert!(flake.contains("keystone.url"));
    assert!(flake.contains("disko.url"));
    assert!(flake.contains("home-manager.url"));
    assert!(flake.contains("keystone.nixosModules.operating-system"));

    assert!(configuration.contains("enable = true;"));
    assert!(configuration.contains("test-host"));
    assert!(configuration.contains("deadbeef"));
    assert!(configuration.contains("stateVersion = \"24.11\""));

    assert_eq!(hardware.trim(), "{ ... }: { }");
}

#[test]
fn test_mirror_zfs_generation() {
    let config = create_mirror_zfs_config();
    let configuration = generate_configuration_nix(&config);
    validate_nix_syntax(&configuration);
    assert!(configuration.contains("mode = \"mirror\""));
}

#[test]
fn test_ext4_simple_generation() {
    let config = create_ext4_simple_config();
    let configuration = generate_configuration_nix(&config);
    validate_nix_syntax(&configuration);
    assert!(configuration.contains("type = \"ext4\""));
}

#[test]
fn test_zfs_desktop_generation() {
    let config = create_zfs_desktop_config();
    let flake = generate_flake_nix(&config);
    let configuration = generate_configuration_nix(&config);

    validate_nix_syntax(&flake);
    validate_nix_syntax(&configuration);

    assert!(flake.contains("keystone.nixosModules.desktop"));
    assert!(configuration.contains("desktop = {"));
    assert!(configuration.contains("enable = true;"));
}
