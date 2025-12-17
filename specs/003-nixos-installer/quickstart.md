# NixOS Installer TUI – Local Development Quickstart

## Prerequisites
- Nix installed (flakes + nix-command enabled).
- QEMU/KVM available for VM tests.
- This repo checked out; run commands from repo root.

## Fast iteration
- Build+run headless test (recommended CI parity):
  ```bash
  ./bin/test-installer
  ```
- Build only:
  ```bash
  ./bin/test-installer --build-only
  ```
- Interactive REPL/console (debug UI flow):
  ```bash
  ./bin/test-installer --interactive
  # then in REPL: start_all(); test_script()
  ```

Notes:
- Script auto-falls back to a local Nix store when the daemon is unavailable.
- Artifacts: `result/` symlink, `.nix/` local store, `.cache/` for fetcher cache.
- VM creds (from build-vm conventions): testuser/testpass; root/root if needed.

## Making UI changes
1. Edit files in `packages/keystone-installer-ui/src/`.
2. Re-run `./bin/test-installer` to validate end-to-end flow.
3. Use `--interactive` to step through screens (network check → disk → encryption → host/user → install).

## What the test covers
- Boots a NixOS VM with the installer service.
- Drives the TUI to perform a local, unencrypted install onto the data disk.
- Verifies installer log, hardware config generation, and basic disk layout.

If the automated test fails, check `/tmp/keystone-install.log` in the VM (tail is printed on failure). Use the interactive mode to reproduce visually.***
