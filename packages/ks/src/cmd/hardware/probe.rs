//! Shared hardware-credential probe.
//!
//! Single source of truth for what `ks hardware report`, `setup`, the
//! first-boot wizard, and `ks doctor` all need to know about the current
//! machine: Secure Boot state, TPM2 device presence, FIDO2 devices,
//! fingerprint reader, and per-LUKS-volume enrollment slots.
//!
//! Detection sub-functions are intentionally split from interpretation:
//! the IO-doing layer reads paths and runs subprocesses, the pure layer
//! turns those facts into the [`HardwareReport`] struct. Pure functions
//! are unit-testable without root or hardware.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use tokio::process::Command;

/// The credstore zvol on `rpool` — keystone's canonical root-disk LUKS
/// volume on ZFS installs. Holds the rootfs encryption keys.
pub const ROOT_CREDSTORE: &str = "/dev/zvol/rpool/credstore";

/// Root LUKS device on non-ZFS (plain ext4/btrfs) installs, where the
/// disk layout uses `disk-root-root` as the LUKS container label.
pub const NON_ZFS_CREDSTORE: &str = "/dev/disk/by-partlabel/disk-root-root";

/// Discover the root credstore device at runtime.
///
/// Checks the ZFS zvol path first (common case), then falls back to the
/// by-partlabel path used on non-ZFS installs. Returns the ZFS path as
/// a last resort so callers that only print the path still see a useful
/// string.
pub fn credstore_device() -> &'static Path {
    if Path::new(ROOT_CREDSTORE).exists() {
        Path::new(ROOT_CREDSTORE)
    } else if Path::new(NON_ZFS_CREDSTORE).exists() {
        Path::new(NON_ZFS_CREDSTORE)
    } else {
        Path::new(ROOT_CREDSTORE)
    }
}

/// The default LUKS slot 0 passphrase shipped by the installer. The
/// install flow uses this as a temporary placeholder; `ks hardware
/// setup` refuses to enroll any other method while this string still
/// unlocks the disk.
pub const DEFAULT_PASSWORD: &str = "keystone";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Top-level snapshot returned by [`probe`]. Renderer (`report.rs`),
/// orchestrator (`setup.rs`), and `ks doctor` all consume this shape.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareReport {
    pub machine: MachineState,
    pub volumes: Vec<LuksVolume>,
    pub warnings: Vec<Warning>,
}

/// Machine-wide hardware that isn't tied to a single LUKS volume:
/// Secure Boot UEFI state, the TPM2 chip, attached FIDO2 devices, and
/// the fingerprint reader. Per-volume enrollment lives on [`LuksVolume`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MachineState {
    pub secure_boot: SecureBootState,
    pub tpm2: TpmDeviceState,
    pub fido2_devices: Vec<Fido2Device>,
    pub fingerprint: FingerprintState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SecureBootState {
    /// Secure Boot is enabled and keys are enrolled.
    Enrolled,
    /// UEFI Audit Mode is on — key changes are allowed, but unsigned
    /// boot artifacts are still permitted.
    AuditMode,
    /// UEFI Setup Mode is on — ready for `sbctl enroll-keys`.
    SetupMode,
    /// Secure Boot disabled at the firmware level. No PCR-7 integrity.
    Disabled,
    /// `/sys/firmware/efi/efivars` not present — non-UEFI system or
    /// efivarfs not mounted.
    NotSupported,
    /// Probe failed for an unexpected reason.
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TpmDeviceState {
    /// `/dev/tpmrm0` exists — TPM2 is available to systemd-cryptenroll.
    Present,
    /// No TPM device file. PCR-bound auto-unlock is unavailable.
    Absent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Fido2Device {
    /// Path returned by `systemd-cryptenroll --fido2-device=list`
    /// (typically `/dev/hidraw*`).
    pub path: String,
    /// Human-readable label, e.g., "YubiKey 5C".
    pub label: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FingerprintState {
    /// Reader detected and `fprintd` is responsive.
    Available,
    /// Reader detected but fprintd is missing or not running.
    HardwareOnly,
    /// No fingerprint hardware found.
    NotDetected,
}

/// A LUKS volume that participates in unlocking the machine at boot or
/// on demand. Each volume has its own four-slot model (password,
/// recovery, TPM2 token, FIDO2 token).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LuksVolume {
    /// Stable id used in `ks hardware disks <id>` (e.g., `root`).
    pub id: String,
    /// Block-device path (e.g., `/dev/zvol/rpool/credstore`).
    pub device: PathBuf,
    /// Role this volume plays in the system.
    pub role: VolumeRole,
    /// When this volume unlocks during the boot chain.
    pub boot_stage: BootStage,
    /// Short human-readable description (e.g., "rootfs encryption keys").
    pub holds: String,
    /// Per-slot enrollment state.
    pub slots: SlotMap,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VolumeRole {
    /// Holds the rootfs encryption keys; required for the machine to boot.
    Primary,
    /// Holds keys for an additional ZFS pool or LUKS volume that unlocks
    /// after root is up (e.g., a NAS data array).
    Secondary,
    /// On-demand unlock — never auto-unlocks; user must run a command.
    Manual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BootStage {
    /// Opened by systemd from initrd before user-space starts.
    Initrd,
    /// Opened after root is mounted (e.g., via a `keylocation=file://`
    /// reference to a key on the unlocked rootfs).
    AfterRoot,
    /// Never auto-opened.
    OnDemand,
}

/// Per-method enrollment state for one LUKS volume.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SlotMap {
    pub password: SlotState,
    pub recovery: SlotState,
    pub tpm2: SlotState,
    pub fido2: SlotState,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SlotState {
    /// Whether this method is currently enrolled on the volume.
    pub enrolled: bool,
    /// Whether this slot is the default-installer placeholder (only
    /// meaningful for `password`).
    pub is_default: bool,
    /// Free-form detail, e.g., "PCRs 1+7" or "YubiKey 5C".
    pub detail: Option<String>,
}

/// A machine-wide or per-volume warning surfaced in the report and the
/// setup plan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Warning {
    pub severity: Severity,
    pub scope: WarningScope,
    pub message: String,
    pub remediation: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    /// Loss-of-data risk if left unresolved.
    Critical,
    /// Degraded security or future loss-of-access risk.
    Warning,
    /// Informational hint.
    Info,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum WarningScope {
    /// Affects the whole machine (e.g., Secure Boot disabled).
    Machine,
    /// Affects a specific LUKS volume by id.
    Volume { id: String },
}

/// LUKS unlock method (and the fingerprint reader, which is in this
/// namespace because it's a hardware credential on the same machine,
/// even though it auths sudo/login rather than the disk itself).
///
/// Manual `FromStr` / `Display` impls instead of a derive macro because
/// the codebase keeps its dependency surface small and the enum is
/// small. If the variant set grows, switch to a `strum` derive.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Method {
    Password,
    Recovery,
    Tpm2,
    Fido2,
    Fingerprint,
}

impl Method {
    /// Methods that unlock a LUKS volume (everything but fingerprint).
    pub const ALL_LUKS: &'static [Method] = &[
        Method::Password,
        Method::Recovery,
        Method::Tpm2,
        Method::Fido2,
    ];

    pub fn as_str(&self) -> &'static str {
        match self {
            Method::Password => "password",
            Method::Recovery => "recovery",
            Method::Tpm2 => "tpm2",
            Method::Fido2 => "fido2",
            Method::Fingerprint => "fingerprint",
        }
    }

    pub fn is_luks_unlock_method(&self) -> bool {
        !matches!(self, Method::Fingerprint)
    }
}

impl std::fmt::Display for Method {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

impl std::str::FromStr for Method {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.trim().to_ascii_lowercase().as_str() {
            "password" | "pw" => Ok(Method::Password),
            "recovery" => Ok(Method::Recovery),
            "tpm2" | "tpm" => Ok(Method::Tpm2),
            "fido2" | "yubikey" | "fido" => Ok(Method::Fido2),
            "fingerprint" | "fpr" => Ok(Method::Fingerprint),
            other => Err(format!(
                "unknown method '{}': expected one of password, recovery, tpm2, fido2, fingerprint",
                other
            )),
        }
    }
}

// ---------------------------------------------------------------------------
// Pure interpreters (testable without IO)
// ---------------------------------------------------------------------------

/// Translate raw efivars byte readings into a [`SecureBootState`].
///
/// The EFI variables `SecureBoot-*` and `SetupMode-*` are 5-byte
/// little-endian blobs: the first 4 are EFI attributes, the 5th is the
/// boolean value. A missing variable means the firmware doesn't expose
/// that state.
pub fn secure_boot_from_efivars(
    secure_boot_var: Option<&[u8]>,
    setup_mode_var: Option<&[u8]>,
    audit_mode_var: Option<&[u8]>,
    efivars_dir_exists: bool,
) -> SecureBootState {
    if !efivars_dir_exists {
        return SecureBootState::NotSupported;
    }
    let sb_on = secure_boot_var.and_then(|b| b.get(4)).copied() == Some(1);
    let setup_on = setup_mode_var.and_then(|b| b.get(4)).copied() == Some(1);
    let audit_on = audit_mode_var.and_then(|b| b.get(4)).copied() == Some(1);
    if sb_on {
        SecureBootState::Enrolled
    } else if audit_on {
        SecureBootState::AuditMode
    } else if setup_on {
        SecureBootState::SetupMode
    } else if secure_boot_var.is_some() || setup_mode_var.is_some() || audit_mode_var.is_some() {
        SecureBootState::Disabled
    } else {
        SecureBootState::Unknown
    }
}

/// Parse one line of `cryptsetup luksDump` output for a slot indicator
/// and return the parsed slot number if present.
///
/// luksDump prints lines like `  0: luks2` (key slots) and `Tokens:`
/// followed by token blocks. We only need to know which numbered
/// keyslots and which named tokens exist — the rest is decoration.
pub fn parse_luks_dump(dump: &str) -> ParsedLuksDump {
    let mut slots = Vec::new();
    let mut tokens = Vec::new();
    let mut in_keyslots = false;
    let mut in_tokens = false;

    for raw in dump.lines() {
        let line = raw.trim_end();
        let trimmed = line.trim_start();
        let indent = line.len() - trimmed.len();

        if indent == 0 {
            in_keyslots = trimmed.starts_with("Keyslots:");
            in_tokens = trimmed.starts_with("Tokens:");
            continue;
        }

        if in_keyslots {
            if let Some(slot) = parse_slot_line(trimmed) {
                slots.push(slot);
            }
        } else if in_tokens {
            if let Some(name) = parse_token_line(trimmed) {
                tokens.push(name);
            }
        }
    }

    ParsedLuksDump { slots, tokens }
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct ParsedLuksDump {
    pub slots: Vec<u8>,
    pub tokens: Vec<String>,
}

fn parse_slot_line(line: &str) -> Option<u8> {
    // "0: luks2" — extract the leading integer.
    let (num, rest) = line.split_once(':')?;
    let n: u8 = num.trim().parse().ok()?;
    if rest.trim().starts_with("luks") {
        Some(n)
    } else {
        None
    }
}

fn parse_token_line(line: &str) -> Option<String> {
    // Token blocks look like:
    //   "  1: systemd-tpm2"
    //   "  2: systemd-fido2"
    let (_num, kind) = line.split_once(':')?;
    let kind = kind.trim();
    if kind.starts_with("systemd-") {
        Some(kind.to_string())
    } else {
        None
    }
}

/// Build a [`SlotMap`] from a parsed luksDump + the result of probing
/// the default-password slot. Pure / testable.
pub fn slotmap_from_dump(dump: &ParsedLuksDump, password_is_default: bool) -> SlotMap {
    let has_pw_slot = dump.slots.contains(&0);
    let has_recovery_slot = dump.slots.contains(&1);
    let has_tpm = dump.tokens.iter().any(|t| t == "systemd-tpm2");
    let has_fido = dump.tokens.iter().any(|t| t == "systemd-fido2");

    SlotMap {
        password: SlotState {
            enrolled: has_pw_slot,
            is_default: has_pw_slot && password_is_default,
            detail: if has_pw_slot {
                Some(if password_is_default {
                    "DEFAULT — must be rotated".into()
                } else {
                    "user passphrase".into()
                })
            } else {
                None
            },
        },
        recovery: SlotState {
            enrolled: has_recovery_slot,
            is_default: false,
            detail: has_recovery_slot.then(|| "paper key".into()),
        },
        tpm2: SlotState {
            enrolled: has_tpm,
            is_default: false,
            detail: has_tpm.then(|| "systemd-tpm2 token".into()),
        },
        fido2: SlotState {
            enrolled: has_fido,
            is_default: false,
            detail: has_fido.then(|| "systemd-fido2 token".into()),
        },
    }
}

/// Compute the warnings that apply to a [`HardwareReport`] given its
/// observed state. Pure / testable.
pub fn warnings_from(report_without_warnings: &HardwareReport) -> Vec<Warning> {
    warnings_from_context(report_without_warnings, WarningContext::InstalledSystem)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WarningContext {
    InstalledSystem,
    LiveInstaller,
}

fn warnings_from_context(
    report_without_warnings: &HardwareReport,
    context: WarningContext,
) -> Vec<Warning> {
    if matches!(context, WarningContext::LiveInstaller) {
        return Vec::new();
    }

    let mut out = Vec::new();

    match report_without_warnings.machine.secure_boot {
        SecureBootState::Disabled => out.push(Warning {
            severity: Severity::Warning,
            scope: WarningScope::Machine,
            message: "Secure Boot is DISABLED.".into(),
            remediation: Some(
                "Run `ks hardware setup` to stage Secure Boot keys, then enable Secure Boot in firmware so TPM PCR-7 binding has an integrity anchor.".into(),
            ),
        }),
        SecureBootState::AuditMode => out.push(Warning {
            severity: Severity::Info,
            scope: WarningScope::Machine,
            message: "UEFI in Audit Mode — Secure Boot enforcement is still disabled.".into(),
            remediation: Some(
                "Run `sbctl verify` to confirm current lanzaboote artifacts are signed, then enable Secure Boot enforcement in firmware and re-run `ks hardware setup`.".into(),
            ),
        }),
        SecureBootState::SetupMode => out.push(Warning {
            severity: Severity::Info,
            scope: WarningScope::Machine,
            message: "UEFI in Setup Mode — Secure Boot keys ready to enroll.".into(),
            remediation: Some(
                "Run `ks hardware setup` to enroll Secure Boot keys and stage the required reboot.".into(),
            ),
        }),
        SecureBootState::NotSupported => out.push(Warning {
            severity: Severity::Info,
            scope: WarningScope::Machine,
            message: "Secure Boot is not supported on this firmware.".into(),
            remediation: None,
        }),
        _ => {}
    }

    for v in &report_without_warnings.volumes {
        if v.slots.password.is_default {
            out.push(Warning {
                severity: Severity::Critical,
                scope: WarningScope::Volume { id: v.id.clone() },
                message: format!(
                    "Volume `{}` still accepts the default installer password.",
                    v.id
                ),
                remediation: Some(format!(
                    "Run `ks hardware enroll password --disk={}` (or `ks hardware setup`).",
                    v.id
                )),
            });
        }
        if !v.slots.tpm2.enrolled {
            out.push(Warning {
                severity: Severity::Warning,
                scope: WarningScope::Volume { id: v.id.clone() },
                message: format!(
                    "Volume `{}` does not have TPM2 automatic unlock enrolled.",
                    v.id
                ),
                remediation: Some(format!(
                    "Run `ks hardware setup` after enrolling Secure Boot to add TPM2 automatic unlock on `{}`.",
                    v.id
                )),
            });
        }

        if !v.slots.recovery.enrolled && !v.slots.fido2.enrolled {
            out.push(Warning {
                severity: Severity::Warning,
                scope: WarningScope::Volume { id: v.id.clone() },
                message: format!(
                    "Volume `{}` has no strong human fallback unlock method.",
                    v.id
                ),
                remediation: Some(
                    "Enroll a FIDO2 hardware key or recovery key; keep a unique host passphrase as manual fallback.".into(),
                ),
            });
        }
    }

    out
}

// ---------------------------------------------------------------------------
// IO-doing layer
// ---------------------------------------------------------------------------

/// Run the full probe and return a [`HardwareReport`].
///
/// Best-effort: failures in any individual sub-probe (e.g., missing
/// efivarfs, no `cryptsetup` on PATH) degrade specific fields but do
/// not abort the report.
pub async fn probe() -> HardwareReport {
    let secure_boot = probe_secure_boot().await;
    let tpm2 = probe_tpm_device().await;
    let fido2_devices = probe_fido2_devices().await;
    let fingerprint = probe_fingerprint().await;
    let volumes = probe_luks_volumes().await;

    let mut report = HardwareReport {
        machine: MachineState {
            secure_boot,
            tpm2,
            fido2_devices,
            fingerprint,
        },
        volumes,
        warnings: Vec::new(),
    };
    let warning_context = if is_live_installer_environment() {
        WarningContext::LiveInstaller
    } else {
        WarningContext::InstalledSystem
    };
    report.warnings = warnings_from_context(&report, warning_context);
    report
}

fn is_live_installer_environment() -> bool {
    [
        "/etc/keystone/install-repo",
        "/etc/keystone/install-config",
        "/etc/keystone/install-metadata",
    ]
    .iter()
    .any(|p| Path::new(p).exists())
}

async fn probe_secure_boot() -> SecureBootState {
    let efivars = Path::new("/sys/firmware/efi/efivars");
    if !efivars.is_dir() {
        return SecureBootState::NotSupported;
    }
    let sb = read_efivar(efivars, "SecureBoot").await;
    let setup = read_efivar(efivars, "SetupMode").await;
    let audit = read_efivar(efivars, "AuditMode").await;
    secure_boot_from_efivars(sb.as_deref(), setup.as_deref(), audit.as_deref(), true)
}

async fn read_efivar(efivars: &Path, name_prefix: &str) -> Option<Vec<u8>> {
    let mut entries = tokio::fs::read_dir(efivars).await.ok()?;
    while let Ok(Some(entry)) = entries.next_entry().await {
        let name = entry.file_name();
        if let Some(s) = name.to_str() {
            if s.starts_with(&format!("{}-", name_prefix)) {
                return tokio::fs::read(entry.path()).await.ok();
            }
        }
    }
    None
}

async fn probe_tpm_device() -> TpmDeviceState {
    if tokio::fs::try_exists("/dev/tpmrm0").await.unwrap_or(false) {
        TpmDeviceState::Present
    } else {
        TpmDeviceState::Absent
    }
}

async fn probe_fido2_devices() -> Vec<Fido2Device> {
    let output = match Command::new("systemd-cryptenroll")
        .args(["--fido2-device=list"])
        .output()
        .await
    {
        Ok(o) if o.status.success() => o,
        _ => return Vec::new(),
    };
    parse_fido2_device_list(&String::from_utf8_lossy(&output.stdout))
}

/// Parse output of `systemd-cryptenroll --fido2-device=list`.
///
/// Sample output:
/// ```text
/// PATH         MANUFACTURER   PRODUCT
/// /dev/hidraw0 Yubico         YubiKey OTP+FIDO+CCID
/// ```
pub fn parse_fido2_device_list(text: &str) -> Vec<Fido2Device> {
    text.lines()
        .skip(1) // header
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let path = parts.next()?;
            let rest: Vec<&str> = parts.collect();
            if path.is_empty() {
                return None;
            }
            Some(Fido2Device {
                path: path.to_string(),
                label: rest.join(" "),
            })
        })
        .collect()
}

async fn probe_fingerprint() -> FingerprintState {
    let fprintd_running = Command::new("systemctl")
        .args(["is-active", "fprintd.service"])
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);
    // libfprint hardware detection is best-effort; absent libfprint
    // dependency in Cargo.toml, we approximate via fprintd activity.
    // A user with a reader but a stopped service still shows up as
    // HardwareOnly here.
    match (fprintd_running, fprintd_hw_seen()) {
        (true, _) => FingerprintState::Available,
        (false, true) => FingerprintState::HardwareOnly,
        (false, false) => FingerprintState::NotDetected,
    }
}

fn fprintd_hw_seen() -> bool {
    // Heuristic: presence of fprintd binary on PATH indicates the
    // distro provisioned for fingerprint hardware. False positives on
    // machines without a reader are acceptable since the reader probe
    // is purely advisory.
    crate::cmd::util::find_executable("fprintd-enroll").is_some()
}

async fn probe_luks_volumes() -> Vec<LuksVolume> {
    // v1.1 scope: only the canonical root credstore is enumerated.
    // Dynamic discovery covers ZFS (`/dev/zvol/rpool/credstore`) and
    // non-ZFS (`/dev/disk/by-partlabel/disk-root-root`) installs.
    // Reading /etc/crypttab + scanning rpool zvols for additional
    // LUKS-protected zvols is a v1.2 expansion.
    let device = PathBuf::from(credstore_device());
    if !device.exists() {
        return Vec::new();
    }

    let dump = match Command::new("cryptsetup")
        .arg("luksDump")
        .arg(&device)
        .output()
        .await
    {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).into_owned(),
        _ => String::new(),
    };
    let parsed = parse_luks_dump(&dump);
    let is_default = default_password_unlocks(&device).await;
    let slots = slotmap_from_dump(&parsed, is_default);

    vec![LuksVolume {
        id: "root".into(),
        device,
        role: VolumeRole::Primary,
        boot_stage: BootStage::Initrd,
        holds: "rootfs encryption keys".into(),
        slots,
    }]
}

async fn default_password_unlocks(device: &Path) -> bool {
    // `cryptsetup open --test-passphrase` reads the passphrase from
    // stdin. We pipe the default string and inspect the exit code.
    let mut child = match Command::new("cryptsetup")
        .args(["open", "--test-passphrase"])
        .arg(device)
        .arg("--key-file=-")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return false,
    };
    if let Some(stdin) = child.stdin.as_mut() {
        use tokio::io::AsyncWriteExt;
        let _ = stdin.write_all(DEFAULT_PASSWORD.as_bytes()).await;
        let _ = stdin.shutdown().await;
    }
    matches!(child.wait().await, Ok(s) if s.success())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn method_roundtrips_through_str() {
        for m in [
            Method::Password,
            Method::Recovery,
            Method::Tpm2,
            Method::Fido2,
            Method::Fingerprint,
        ] {
            assert_eq!(m.as_str().parse::<Method>().unwrap(), m);
        }
    }

    #[test]
    fn method_accepts_common_aliases() {
        assert_eq!("pw".parse::<Method>().unwrap(), Method::Password);
        assert_eq!("tpm".parse::<Method>().unwrap(), Method::Tpm2);
        assert_eq!("yubikey".parse::<Method>().unwrap(), Method::Fido2);
        assert_eq!("fpr".parse::<Method>().unwrap(), Method::Fingerprint);
    }

    #[test]
    fn method_rejects_unknown() {
        assert!("hopium".parse::<Method>().is_err());
    }

    #[test]
    fn fingerprint_is_not_a_luks_unlock_method() {
        assert!(!Method::Fingerprint.is_luks_unlock_method());
        for m in Method::ALL_LUKS {
            assert!(m.is_luks_unlock_method());
        }
    }

    #[test]
    fn efivars_secure_boot_byte_5_is_the_truth() {
        // 5-byte efivar: 4 attribute bytes + 1 value byte.
        let on = vec![0, 0, 0, 0, 1];
        let off = vec![0, 0, 0, 0, 0];
        assert_eq!(
            secure_boot_from_efivars(Some(&on), Some(&off), Some(&off), true),
            SecureBootState::Enrolled
        );
        assert_eq!(
            secure_boot_from_efivars(Some(&off), Some(&on), Some(&off), true),
            SecureBootState::SetupMode
        );
        assert_eq!(
            secure_boot_from_efivars(Some(&off), Some(&off), Some(&off), true),
            SecureBootState::Disabled
        );
    }

    #[test]
    fn efivars_audit_mode_is_not_plain_setup_mode() {
        let off = vec![0, 0, 0, 0, 0];
        let on = vec![0, 0, 0, 0, 1];
        assert_eq!(
            secure_boot_from_efivars(Some(&off), Some(&on), Some(&on), true),
            SecureBootState::AuditMode
        );
    }

    #[test]
    fn efivars_missing_dir_means_not_supported() {
        assert_eq!(
            secure_boot_from_efivars(None, None, None, false),
            SecureBootState::NotSupported
        );
    }

    #[test]
    fn efivars_missing_vars_with_dir_means_unknown() {
        assert_eq!(
            secure_boot_from_efivars(None, None, None, true),
            SecureBootState::Unknown
        );
    }

    #[test]
    fn luks_dump_parser_finds_slots_and_systemd_tokens() {
        let dump = "\
LUKS header information
Version: 2
Keyslots:
  0: luks2
        Key:        512 bits
  1: luks2
        Key:        512 bits
Tokens:
  0: systemd-tpm2
        tpm2-pcrs:  1,7
  1: systemd-fido2
        fido2-rp:   io.systemd.cryptsetup
Digests:
  0: pbkdf2
";
        let parsed = parse_luks_dump(dump);
        assert_eq!(parsed.slots, vec![0, 1]);
        assert_eq!(parsed.tokens, vec!["systemd-tpm2", "systemd-fido2"]);
    }

    #[test]
    fn luks_dump_parser_ignores_non_systemd_tokens() {
        let dump = "\
Keyslots:
  0: luks2
Tokens:
  0: keyring
  1: systemd-tpm2
";
        let parsed = parse_luks_dump(dump);
        assert_eq!(parsed.tokens, vec!["systemd-tpm2"]);
    }

    #[test]
    fn slotmap_marks_default_password_when_probe_says_so() {
        let parsed = ParsedLuksDump {
            slots: vec![0],
            tokens: vec![],
        };
        let m = slotmap_from_dump(&parsed, true);
        assert!(m.password.enrolled);
        assert!(m.password.is_default);
        assert_eq!(
            m.password.detail.as_deref(),
            Some("DEFAULT — must be rotated")
        );
    }

    #[test]
    fn slotmap_with_full_enrollment_is_not_default() {
        let parsed = ParsedLuksDump {
            slots: vec![0, 1],
            tokens: vec!["systemd-tpm2".into(), "systemd-fido2".into()],
        };
        let m = slotmap_from_dump(&parsed, false);
        assert!(m.password.enrolled && !m.password.is_default);
        assert!(m.recovery.enrolled);
        assert!(m.tpm2.enrolled);
        assert!(m.fido2.enrolled);
    }

    #[test]
    fn warnings_flag_default_password() {
        let r = HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Enrolled,
                tpm2: TpmDeviceState::Present,
                fido2_devices: vec![],
                fingerprint: FingerprintState::NotDetected,
            },
            volumes: vec![LuksVolume {
                id: "root".into(),
                device: PathBuf::from("/dev/zvol/rpool/credstore"),
                role: VolumeRole::Primary,
                boot_stage: BootStage::Initrd,
                holds: "rootfs".into(),
                slots: SlotMap {
                    password: SlotState {
                        enrolled: true,
                        is_default: true,
                        detail: Some("DEFAULT".into()),
                    },
                    ..Default::default()
                },
            }],
            warnings: vec![],
        };
        let w = warnings_from(&r);
        assert!(w.iter().any(|x| matches!(x.severity, Severity::Critical)
            && matches!(&x.scope, WarningScope::Volume { id } if id == "root")));
    }

    #[test]
    fn warnings_flag_secure_boot_disabled_globally() {
        let r = HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Disabled,
                tpm2: TpmDeviceState::Present,
                fido2_devices: vec![],
                fingerprint: FingerprintState::NotDetected,
            },
            volumes: vec![],
            warnings: vec![],
        };
        let w = warnings_from(&r);
        assert!(
            w.iter()
                .any(|x| matches!(x.scope, WarningScope::Machine)
                    && x.message.contains("Secure Boot"))
        );
    }

    #[test]
    fn warnings_are_suppressed_in_live_installer_context() {
        let r = HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Disabled,
                tpm2: TpmDeviceState::Absent,
                fido2_devices: vec![],
                fingerprint: FingerprintState::NotDetected,
            },
            volumes: vec![LuksVolume {
                id: "root".into(),
                device: PathBuf::from("/dev/zvol/rpool/credstore"),
                role: VolumeRole::Primary,
                boot_stage: BootStage::Initrd,
                holds: "rootfs encryption keys".into(),
                slots: SlotMap {
                    password: SlotState {
                        enrolled: true,
                        is_default: true,
                        detail: None,
                    },
                    recovery: SlotState::default(),
                    tpm2: SlotState::default(),
                    fido2: SlotState::default(),
                },
            }],
            warnings: vec![],
        };

        assert!(warnings_from_context(&r, WarningContext::LiveInstaller).is_empty());
        assert!(warnings_from_context(&r, WarningContext::InstalledSystem).len() >= 3);
    }

    #[test]
    fn warnings_flag_missing_strong_human_fallback() {
        let r = HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Enrolled,
                tpm2: TpmDeviceState::Present,
                fido2_devices: vec![],
                fingerprint: FingerprintState::NotDetected,
            },
            volumes: vec![LuksVolume {
                id: "tank".into(),
                device: PathBuf::from("/dev/zvol/rpool/tank-keystore"),
                role: VolumeRole::Secondary,
                boot_stage: BootStage::AfterRoot,
                holds: "tank pool key".into(),
                slots: SlotMap {
                    password: SlotState {
                        enrolled: true,
                        is_default: false,
                        detail: None,
                    },
                    ..Default::default()
                },
            }],
            warnings: vec![],
        };
        let w = warnings_from(&r);
        assert!(w.iter().any(|x| matches!(x.severity, Severity::Warning)
            && matches!(&x.scope, WarningScope::Volume { id } if id == "tank")
            && x.message.contains("strong human fallback")));
        assert!(w.iter().any(|x| x
            .remediation
            .as_deref()
            .unwrap_or_default()
            .contains("FIDO2 hardware key or recovery key")));
    }

    #[test]
    fn warnings_flag_missing_tpm_automatic_unlock_separately() {
        let r = HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Enrolled,
                tpm2: TpmDeviceState::Present,
                fido2_devices: vec![],
                fingerprint: FingerprintState::NotDetected,
            },
            volumes: vec![LuksVolume {
                id: "root".into(),
                device: PathBuf::from("/dev/zvol/rpool/credstore"),
                role: VolumeRole::Primary,
                boot_stage: BootStage::Initrd,
                holds: "rootfs".into(),
                slots: SlotMap {
                    password: SlotState {
                        enrolled: true,
                        is_default: false,
                        detail: None,
                    },
                    recovery: SlotState {
                        enrolled: true,
                        is_default: false,
                        detail: Some("paper key".into()),
                    },
                    ..Default::default()
                },
            }],
            warnings: vec![],
        };
        let w = warnings_from(&r);
        assert!(w
            .iter()
            .any(|x| x.message.contains("TPM2 automatic unlock")));
        assert!(!w
            .iter()
            .any(|x| x.message.contains("strong human fallback")));
    }

    #[test]
    fn warnings_clear_when_password_recovery_and_tpm_are_enrolled() {
        let r = HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Enrolled,
                tpm2: TpmDeviceState::Present,
                fido2_devices: vec![],
                fingerprint: FingerprintState::NotDetected,
            },
            volumes: vec![LuksVolume {
                id: "root".into(),
                device: PathBuf::from("/dev/zvol/rpool/credstore"),
                role: VolumeRole::Primary,
                boot_stage: BootStage::Initrd,
                holds: "rootfs".into(),
                slots: SlotMap {
                    password: SlotState {
                        enrolled: true,
                        is_default: false,
                        detail: Some("user passphrase".into()),
                    },
                    recovery: SlotState {
                        enrolled: true,
                        is_default: false,
                        detail: Some("paper key".into()),
                    },
                    tpm2: SlotState {
                        enrolled: true,
                        is_default: false,
                        detail: Some("systemd-tpm2 token".into()),
                    },
                    ..Default::default()
                },
            }],
            warnings: vec![],
        };
        assert!(warnings_from(&r).is_empty());
    }

    #[test]
    fn fido2_device_list_parser_handles_typical_output() {
        let text = "\
PATH         MANUFACTURER PRODUCT
/dev/hidraw0 Yubico       YubiKey OTP+FIDO+CCID
";
        let devs = parse_fido2_device_list(text);
        assert_eq!(devs.len(), 1);
        assert_eq!(devs[0].path, "/dev/hidraw0");
        assert!(devs[0].label.contains("YubiKey"));
    }

    #[test]
    fn fido2_device_list_parser_handles_no_devices() {
        let text = "PATH MANUFACTURER PRODUCT\n";
        assert!(parse_fido2_device_list(text).is_empty());
    }
}
