# NixOS Installer TUI Specification

## Overview
- Goal: Provide a guided terminal installer for Keystone that can deploy a NixOS system (server or client) onto a target disk with minimal prompts.
- Scope: Runs on the installer ISO; supports local installs first (unencrypted + encrypted paths), with room for remote/clone flows later.
- Automation: Must be fully testable headlessly via VM tests (`./bin/test-installer`) to gate changes in CI.

## Functional Requirements
- Startup: Present network status and block progression until basic connectivity is confirmed (or provide a clear retry path).
- Install methods: Offer at least “Local installation” (on this machine); keep stubs for remote/clone as future options.
- Disk handling:
  - Enumerate installable disks and surface size/model hints.
  - Confirm destructive actions before proceeding.
  - Support unencrypted ext4 path; plan for encrypted ZFS/LUKS flow.
  - Use generated disko configs; ensure target mounts land at `/mnt` for subsequent steps.
- Host/user inputs: Collect hostname, username, and password with validation and confirmation.
- System type: Allow choosing server vs client module set for generated flake config.
- Config generation: Produce flake + host files, disko config(s), and hardware configuration under `/mnt/home/<user>/nixos-config`.
- Install execution: Run `nixos-install` with the generated flake; set user password; log all operations to `/tmp/keystone-install.log`.
- Logging/UX: Stream progress and errors; provide tail of the install log on failure.

## Non-Functional Requirements
- Automated testing: The full happy path must run headlessly in VM tests via `./bin/test-installer`; failures should exit non-zero and print diagnostic tails.
- Determinism: Avoid reliance on external state (network checks may use a simple local IP presence test).
- Observability: Operations (partitioning, mounts, config moves, install) must be logged with timestamps to `/tmp/keystone-install.log`.
- Resilience: If automatic mounts fail, surface clear errors; continue logging to aid debugging.

## Out of Scope (for now)
- Secure Boot/TPM2 flows during install.
- Remote/clone install workflows beyond stubs.
- Post-install reboot orchestration.***
