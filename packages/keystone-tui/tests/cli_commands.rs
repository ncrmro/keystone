//! CLI command integration tests.
//!
//! Tests the CLI subcommand routing, JSON output, and repo discovery
//! without requiring nix or an actual nixos-config repo.

use ks::cmd;

#[test]
fn json_output_envelope_ok() {
    let output = cmd::JsonOutput::ok("hello");
    let json = serde_json::to_value(&output).unwrap();
    assert_eq!(json["status"], "ok");
    assert_eq!(json["data"], "hello");
}

#[test]
fn json_output_envelope_with_struct() {
    let result = cmd::build::BuildResult {
        hosts: vec!["workstation".to_string(), "ocean".to_string()],
        lock: true,
        store_paths: vec![
            "/nix/store/abc-system".to_string(),
            "/nix/store/def-system".to_string(),
        ],
    };
    let output = cmd::JsonOutput::ok(&result);
    let json = serde_json::to_value(&output).unwrap();
    assert_eq!(json["status"], "ok");
    assert_eq!(json["data"]["hosts"][0], "workstation");
    assert_eq!(json["data"]["hosts"][1], "ocean");
    assert_eq!(json["data"]["lock"], true);
    assert_eq!(json["data"]["store_paths"].as_array().unwrap().len(), 2);
}

#[test]
fn json_error_envelope() {
    let err = cmd::JsonError::new("build failed");
    let json = serde_json::to_value(&err).unwrap();
    assert_eq!(json["status"], "error");
    assert_eq!(json["error"], "build failed");
}

#[test]
fn build_result_empty_hosts() {
    let result = cmd::build::BuildResult {
        hosts: vec![],
        lock: false,
        store_paths: vec![],
    };
    let json = serde_json::to_string(&result).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert!(parsed["hosts"].as_array().unwrap().is_empty());
}

#[test]
fn switch_result_modes() {
    let switch = cmd::switch::SwitchResult {
        hosts: vec!["laptop".to_string()],
        mode: "switch".to_string(),
        store_paths: vec!["/nix/store/xxx".to_string()],
    };
    let json = serde_json::to_value(&switch).unwrap();
    assert_eq!(json["mode"], "switch");

    let boot = cmd::switch::SwitchResult {
        hosts: vec!["server".to_string()],
        mode: "boot".to_string(),
        store_paths: vec![],
    };
    let json = serde_json::to_value(&boot).unwrap();
    assert_eq!(json["mode"], "boot");
}

#[test]
fn update_result_dev_vs_lock() {
    let dev = cmd::update::UpdateResult {
        hosts: vec!["workstation".to_string()],
        dev: true,
        mode: "switch".to_string(),
    };
    let json = serde_json::to_value(&dev).unwrap();
    assert_eq!(json["dev"], true);
    assert_eq!(json["mode"], "switch");

    let lock = cmd::update::UpdateResult {
        hosts: vec!["ocean".to_string()],
        dev: false,
        mode: "boot".to_string(),
    };
    let json = serde_json::to_value(&lock).unwrap();
    assert_eq!(json["dev"], false);
    assert_eq!(json["mode"], "boot");
}

#[test]
fn doctor_report_structure() {
    let report = cmd::doctor::DoctorReport {
        hostname: "test-host".to_string(),
        nixos_generation: Some("25.05.abc".to_string()),
        checks: vec![
            cmd::doctor::DiagnosticCheck {
                name: "systemd-units".to_string(),
                status: "ok".to_string(),
                detail: "No failed units".to_string(),
            },
            cmd::doctor::DiagnosticCheck {
                name: "disk-usage".to_string(),
                status: "ok".to_string(),
                detail: "Disk usage collected".to_string(),
            },
            cmd::doctor::DiagnosticCheck {
                name: "flake-lock-age".to_string(),
                status: "ok".to_string(),
                detail: "Last updated: 2 days ago".to_string(),
            },
        ],
        markdown: "## System State\n_None_\n".to_string(),
    };

    let json = serde_json::to_value(&report).unwrap();
    assert_eq!(json["hostname"], "test-host");
    assert_eq!(json["nixos_generation"], "25.05.abc");
    assert_eq!(json["checks"].as_array().unwrap().len(), 3);
    assert_eq!(json["checks"][0]["name"], "systemd-units");
    assert!(json["markdown"].as_str().unwrap().contains("System State"));
}

#[test]
fn doctor_report_no_generation() {
    let report = cmd::doctor::DoctorReport {
        hostname: "mac-host".to_string(),
        nixos_generation: None,
        checks: vec![],
        markdown: String::new(),
    };
    let json = serde_json::to_value(&report).unwrap();
    assert!(json["nixos_generation"].is_null());
}
