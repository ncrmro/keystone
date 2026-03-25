# Spec: First-boot hardware pushback

## Stories Covered
- US-010: Post-install hardware pushback

## Affected Modules
- `packages/keystone-tui/src/screens/first_boot.rs` - first-boot orchestration and user-visible status
- `packages/keystone-tui/src/screens/install.rs` - installer contract for data persisted into the installed system
- `packages/keystone-tui/src/app.rs` - boot-mode routing into `FirstBootScreen`
- `packages/keystone-tui/src/repo.rs` - git add, commit, remote, and push helpers to be extracted from the screen
- `packages/keystone-tui/src/template.rs` - placeholders and generated file contract consumed by first-boot reconciliation

## Existing State

The current first-boot flow already does four useful things:

1. Detects first boot via `~/.keystone/repos/nixos-config/.first-boot-pending`
2. Runs `nixos-generate-config --show-hardware-config`
3. Writes `hardware.nix` into the checked-out flake repo
4. Initializes git, commits, and can push to a remote

That is close to the required product behavior, but it is not yet a true hardware pushback pipeline.
The current flow overwrites `hardware.nix` with raw generator output and does not explicitly reconcile:

- disk identifiers selected during install versus actual booted hardware
- kernel modules and firmware requirements
- patch provenance for review before commit
- retry-safe behavior if pushback runs more than once

## Data models

### `FirstBootHardwareFacts` (new)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `hostname` | `String` | yes | Host being reconciled |
| `generated_at` | `String` | yes | ISO 8601 timestamp for auditability |
| `disk_devices` | `Vec<DetectedDisk>` | yes | Actual block devices observed after boot |
| `kernel_modules` | `Vec<String>` | yes | Normalized module names required by the installed system |
| `firmware_packages` | `Vec<String>` | no | Extra firmware packages inferred from hardware |
| `source` | `HardwareFactsSource` | yes | `nixos-generate-config`, `lsblk`, `udevadm`, or similar |

### `DetectedDisk` (new)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `path` | `String` | yes | Runtime device path such as `/dev/disk/by-id/...` |
| `serial` | `Option<String>` | no | Stable hardware identifier when available |
| `wwn` | `Option<String>` | no | Stable device identifier when available |
| `matches_install_placeholder` | `bool` | yes | Whether this device satisfies an install-time placeholder |

### `PushbackPatchPlan` (new)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `hardware_nix_path` | `PathBuf` | yes | File to patch |
| `diff_preview` | `String` | yes | Human-readable diff shown before commit |
| `warnings` | `Vec<String>` | yes | Any mismatches or incomplete detection results |
| `commit_message` | `String` | yes | Default commit message for accepted changes |

## Behavioral requirements

### Detection and fact gathering

1. On first boot, the system MUST detect whether hardware pushback is pending by checking for the existing marker file consumed by `FirstBootConfig::detect`.
2. The first-boot flow MUST collect actual hardware facts from the running system before proposing any repo changes.
3. The hardware facts collection MUST include:
   - stable disk identifiers where available
   - generated `hardware.nix` content from `nixos-generate-config`
   - required kernel modules present in the generated hardware config
4. The pushback flow SHOULD collect firmware-relevant hints when they can be derived safely from the generated hardware config.
5. The system MUST preserve a normalized, in-memory `FirstBootHardwareFacts` structure before writing files.

### Patch generation

6. The pushback flow MUST generate a patch plan rather than writing raw `hardware.nix` output directly to git without review.
7. The patch plan MUST update `hardware.nix` with the booted machine's actual identifiers and module requirements.
8. If the generated config still contains install-time placeholders such as `__KEYSTONE_DISK__`, the patch plan MUST replace them with detected stable identifiers when a confident match exists.
9. If the flow cannot confidently map a detected disk to an install placeholder, it MUST warn the user and MUST NOT silently guess.
10. The patch plan MAY update other generated files only when those files contain machine-specific placeholders created during install.
11. The first implementation SHOULD scope automatic edits to `hardware.nix` and explicitly report any recommended follow-up edits outside that file.

### User review and confirmation

12. The first-boot screen MUST show a review step before applying file changes.
13. The review step MUST include:
   - which files will change
   - a summary of detected hardware facts
   - any warnings or partial detections
14. The user MUST be able to accept or skip the patch application.
15. If the user skips the patch, the marker file MUST remain so the flow can be retried later.

### Commit and push behavior

16. After patch application, the flow MUST stage only the files that belong to hardware pushback.
17. The default commit message MUST clearly identify the reconciliation action, for example `feat(keystone-tui): reconcile first-boot hardware for <hostname>`.
18. The flow MUST NOT push to a remote without explicit user confirmation.
19. If a remote is not configured, the flow SHOULD still complete the local patch and local commit successfully.
20. The flow MUST remove the first-boot marker only after patch generation succeeds and the user either commits the result or explicitly dismisses the pending flow.

### Idempotency and retry safety

21. Re-running first-boot pushback on a machine that already reconciled successfully MUST produce no diff or an explicitly empty patch result.
22. If `hardware.nix` already matches the detected hardware facts, the flow MUST report that no patch is needed and MUST exit cleanly.
23. A partial failure after file write but before commit MUST leave the repo in a recoverable state and surface the exact git or filesystem error.

## Edge cases

- If `nixos-generate-config` fails, the flow MUST surface stderr and MUST NOT modify the repo.
- If no stable `/dev/disk/by-id` path exists for a detected disk, the flow SHOULD fall back to the best available identifier and warn that the identifier may be less stable.
- If the git repo is dirty before pushback starts, the flow MUST show the user the pre-existing changes and MUST refuse to auto-commit mixed work.
- If the remote push fails, the local commit MUST remain intact and the screen MUST offer retry instructions rather than rolling back.
- If the machine boots without network access, hardware detection and local patch generation MUST still work; only push should be deferred.

## UI mockup

```
┌─ First boot: hardware reconciliation ───────────────────────────────────┐
│  Host: titan                                                           │
│                                                                        │
│  Detected hardware                                                     │
│  • Disk: /dev/disk/by-id/nvme-Samsung_990_PRO_2TB                      │
│  • Kernel modules: nvme, xhci_pci, thunderbolt                         │
│  • Firmware packages: none                                             │
│                                                                        │
│  Planned patch                                                         │
│  • Update hardware.nix with stable disk identifiers                    │
│  • Keep configuration.nix unchanged                                    │
│                                                                        │
│  [v] View diff   [Enter] Apply and commit   [s] Skip for now          │
└────────────────────────────────────────────────────────────────────────┘
```

## Cross-references

- Spec 001 (Config Generation Contract): install-time placeholders and generated file structure determine what can be reconciled safely on first boot.
- Spec 004 (TUI App Framework): first-boot mode is a dedicated app entry path and shares git confirmation behavior with initial repo publishing.
