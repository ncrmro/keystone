# Plan – NixOS Installer TUI & Automated Testing

## Objectives
- Deliver a guided NixOS installer TUI that meets the functional requirements (FR-001…FR-011).
- Ensure the flow is continuously testable headlessly via `./bin/test-installer` and CI.

## Work Breakdown
1) Baseline TUI flow
   - Implement startup/network gate (FR-001).
   - Provide install method selection with local path (FR-002).
   - Gather hostname/user/password with validation (FR-007) and system role (FR-008).
2) Disk workflow
   - Enumerate disks with metadata and selection UI (FR-003).
   - Add destructive confirmation step (FR-004).
   - Support unencrypted ext4; scaffold encrypted ZFS/LUKS path (FR-005).
   - Generate disko configs and ensure mounts end up at `/mnt` (FR-006, FR-009).
3) Install execution
   - Generate flake + host files + hardware config under `/mnt/home/<user>/nixos-config` (FR-009).
   - Run `nixos-install`, set user password, log operations to `/tmp/keystone-install.log` (FR-010).
   - Stream progress and error tails to the UI (FR-011).
4) Automated test harness
   - Maintain `tests/installer-test.nix` VM test that drives the TUI end-to-end headlessly.
   - Keep `./bin/test-installer` usable headless and interactive; support daemonless/local store use.
   - Include log tail on failure and minimal post-install assertions (hardware-config presence).
5) QA / hardening
   - Interactive REPL smoke tests for UI regressions.
   - Validate disk selection order and confirmations.
   - Verify log coverage for all install phases.

## Validation / CI hooks
- Primary: `./bin/test-installer` (headless).
- Debug: `./bin/test-installer --interactive` for manual stepping.
- Artifacts: `/tmp/keystone-install.log`, VM build logs via `nix log`.
