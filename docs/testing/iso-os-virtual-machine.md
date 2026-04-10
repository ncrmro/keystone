---
title: ISO and OS virtual machine testing
description: End-to-end testing of template generation, installer ISO, and desktop validation in QEMU
---

# ISO and OS virtual machine testing

## Goal

Validate the full Keystone onboarding chain in a VM before touching real hardware:

1. `mkSystemFlake` template generation produces a valid NixOS config
2. The installer ISO boots and `ks` can install a host
3. The installed system boots, reaches the Hyprland desktop, and shows hyprlock
4. SSH works post-reboot with declarative keys from `admin.sshKeys`

When the VM passes, the same template-generated ISO works on real hardware.

## What lives in the ISO vs what is evaluated at install time

Understanding this boundary is the key to fast iteration.

### Baked into the ISO (rebuild required to change)

| Component | Files |
|-----------|-------|
| `ks` binary | `packages/ks/src/` |
| Installer NixOS modules | `modules/iso-installer.nix`, `modules/installer.nix` |
| Live environment packages | Tools in the ISO's squashfs closure |
| Embedded config repo snapshot | Copied from the template at ISO build time |

### Evaluated from the flake during nixos-install (no rebuild)

| Component | Files |
|-----------|-------|
| NixOS modules | `modules/os/`, `modules/desktop/`, `modules/server/` |
| Template library | `lib/templates.nix` (`mkSystemFlake`, `mkLaptop`, etc.) |
| Template flake config | `templates/default/flake.nix` |
| Host definitions | `templates/default/hosts/` |
| SSH keys | `admin.sshKeys` in the template flake |

These are resolved when `nixos-install --flake <repo>#laptop` runs inside the
VM. Changes take effect by updating the fixture's keystone flake input.

### Host-side only (never in the ISO)

| Component | Files |
|-----------|-------|
| `test-iso` script | `templates/default/bin/test-iso` |
| QEMU flags | Memory, GPU, display backend |
| Screenshot capture | `screendump` via QEMU monitor |
| Checkpoint validation | SSH-based checks from the host |

## Quick iteration workflow

### First run (creates fixture and builds ISO)

```bash
cd /tmp/keystone-dev-template-fixture   # or any consumer repo
./bin/test-iso --dev --headless --e2e --port 12260 --memory 12288
```

### After changing NixOS modules or lib/templates.nix

No ISO rebuild needed — the modules are evaluated during `nixos-install`:

```bash
cd /tmp/keystone-dev-template-fixture
nix flake update keystone                # pick up worktree changes
./bin/test-iso --dev --headless --e2e --port 12260 --no-build --memory 12288
```

### After changing the ks binary

ISO rebuild required — the binary is baked into the live environment:

```bash
./bin/test-iso --dev --headless --e2e --port 12260 --memory 12288
```

### After changing only the test-iso script

Copy the updated script, no rebuild:

```bash
cp <worktree>/templates/default/bin/test-iso bin/test-iso
./bin/test-iso --dev --headless --e2e --port 12260 --no-build --memory 12288
```

## Editing files on a running ISO

SSH into the live ISO to test changes without rebuilding:

```bash
ssh -i .test-iso-dev-key -p 12260 keystone@localhost
```

The embedded config repo is read-only (squashfs). When `ks` starts an install,
it copies the repo to `/tmp/keystone-install-repo` (writable). You can edit
files there before the install runs `nixos-install`.

## Post-install iteration

After a successful install, the installed system's config lives at
`/mnt/home/<user>/.keystone/repos/<owner>/<repo>/`. To iterate on the installed
system without re-running the full install:

1. Edit keystone modules or template config in the worktree
2. `nix flake update keystone` in the fixture
3. Copy the updated flake into the VM's installed repo via `scp`
4. Run `nixos-rebuild switch --flake <repo>#laptop` inside the VM via SSH

This is useful for fixing desktop, login, or service issues after install.

## Headless install with ks install --host

Skip the TUI entirely for automated testing:

```bash
# On the live ISO (via SSH):
ks install --host laptop
```

This auto-discovers disks, selects the first one, and streams output to stderr.
Exit code 0 means success. The `--e2e` flag in `test-iso` uses this internally.

## Screenshot-based reboot validation

The `--e2e` flag in `test-iso` adds a second layer after install completes:

1. Kills the ISO VM
2. Boots the installed disk with `virtio-gpu-pci` + `-display egl-headless`
3. Takes QEMU monitor screenshots at each boot stage via `screendump` + `socat`
4. Unlocks LUKS via `sendkey`
5. Validates SSH connectivity with the dev key
6. Compares screenshot SHA256 against committed references in Git LFS

Screenshot stages:

| Stage | What to expect |
|-------|----------------|
| 01-luks-prompt | LUKS passphrase prompt (text console) |
| 02-post-unlock | Boot progress after disk unlock |
| 03-desktop-or-login | Hyprland/hyprlock lockscreen |
| 04-final-state | Final state after login timeout |

First run saves baseline screenshots and hashes. Subsequent runs compare against
the baseline and fail on SHA mismatch.

## VM lifecycle: bin/virtual-machine

`test-iso --e2e` delegates VM lifecycle to `bin/virtual-machine` (in the keystone
repo) via `$KEYSTONE_LOCKED_PATH/bin/virtual-machine`. This is a Python/libvirt
script that provides the proven Q35 + EDK2 SecureBoot + TPM + QXL configuration.

`test-iso` resolves the keystone repo path from `flake.lock` automatically.

```bash
# What test-iso --e2e does internally:
VM_SCRIPT="$KEYSTONE_LOCKED_PATH/bin/virtual-machine"

# Install phase
"$VM_SCRIPT" --name e2e-install --iso "$iso" --disk-path "$disk" \
  --memory 12288 --ssh-port 12260 --headless --start --wait-ssh

# After install completes
"$VM_SCRIPT" --post-install-reboot e2e-install \
  --headless --monitor-socket /tmp/e2e-monitor.sock

# Cleanup
"$VM_SCRIPT" --reset e2e-install
```

### Why libvirt instead of raw QEMU

- OVMF boot device discovery works correctly (proven in `bin/test-deployment`)
- TPM 2.0 via swtpm is managed by libvirt automatically
- Disk snapshots for quick revert
- Consistent PCI topology between install and reboot phases
- QXL display provides a framebuffer for `screendump` even headless

### hardware.graphics

`modules/desktop/nixos.nix` enables `hardware.graphics = true` when desktop is
enabled. This pulls in mesa + virgl drivers so Hyprland can render on the QXL
device in VMs and on real GPUs on bare metal.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| OOM during nixos-install | VM needs more RAM | `--memory 12288` (12 GB) |
| `Holding login session` | No GPU device in QEMU | Ensure `virtio-gpu-pci` + `egl-headless` |
| System profile not detected by checkpoint | Symlink chain doesn't resolve on ISO | Use `test -L` not `test -f` |
| `Cannot find terminfo for xterm-ghostty` | Host TERM passed to VM | Set `TERM=xterm-256color` |
| SSH rejected post-reboot | `admin.sshKeys` not bridged to installed system | Check `lib/templates.nix` `adminSshKeys` bridge |
| nixos-install rebuilds from source | Closure not in cache | Run `bin/warm-cachix` or `nix build .#nixosConfigurations.laptop.config.system.build.toplevel` on the host first |

## Existing VM test infrastructure

`bin/virtual-machine` is the canonical VM tool. All VM workflows should converge
on it. See #339 for the consolidation plan.

| Script | Tier | Machine | SecureBoot | TPM | Display | Purpose |
|--------|------|---------|-----------|-----|---------|---------|
| `bin/virtual-machine` | 3 | Q35 | EDK2 | tpm-crb | SPICE+QXL | Full libvirt VM lifecycle |
| `bin/test-deployment` | 3 | (via virtual-machine) | Yes | Yes | — | nixos-anywhere workflow |
| `bin/build-vm` | 2 | — | No | No | — | Fast nixos-rebuild iteration |
| `bin/test-microvm-tpm` | 1 | Q35 | No | tpm-tis | — | Lightweight TPM test (~20s) |
| `test-iso --e2e` | — | Q35 | No | No | QXL | Template → ISO → install → desktop |

Test configs in `tests/flake.nix`: `test-server`, `test-hyprland`, `build-vm-terminal`,
`build-vm-desktop`, `tpm-microvm`.

## Target architecture

The unified e2e pipeline validates the full new-user journey. One command:

```
./bin/test-iso --dev --headless --e2e --port 12260 --memory 12288
```

Stages (current status):

| # | Stage | Status | Requirement |
|---|-------|--------|-------------|
| 1 | Template generation (`mkSystemFlake`) | Working | REQ-008.3 |
| 2 | ISO build + artifact verification | Working | REQ-003 |
| 3 | Headless install (`ks install --host`) | Working | REQ-008.12-18 |
| 4 | Install checkpoint verification | Working | REQ-003 |
| 5 | Reboot from installed disk | Pending — OVMF boot discovery (#339) | REQ-008.20 |
| 6 | LUKS unlock via QEMU `sendkey` | Working (when boot succeeds) | — |
| 7 | Screenshot capture at boot stages | Working (PPM via `screendump`) | — |
| 8 | Desktop validation (Hyprland + hyprlock) | Pending — needs QXL + boot fix | REQ-002 |
| 9 | SSH validation with dev key | Working | — |
| 10 | SHA-to-SHA screenshot comparison | Working (LFS baselines) | — |

### Future stages (separate issues)

- SecureBoot enrollment (sbctl + lanzaboote) — #283
- TPM enrollment (systemd-cryptenroll) — #283
- First-boot wizard completion — REQ-008.20-23
- Service provisioning — #228

## Requirements traceability

| Requirement | What it covers | Where tested |
|------------|----------------|--------------|
| REQ-003 | Build and e2e validation: template eval, ISO, VM test matrix | `test-iso --e2e` stages 1-4 |
| REQ-008 | Onboarding journey: template → install → first boot → services | `test-iso --e2e` stages 1-9 |
| REQ-001 | Config generation: flake.nix, hosts, hardware.nix | `nix flake check` (eval tests) |
| REQ-002 | Template data model: storage, security, desktop | Desktop screenshot validation |

## Screenshot standardization

All VM testing uses a standard screenshot pipeline:

1. QEMU monitor `screendump <path>.ppm` via `socat` to the monitor socket
2. Convert PPM → PNG via `imagemagick` (`magick` or `convert`)
3. SHA256 hash for regression comparison
4. Reference images committed to Git LFS at `templates/default/tests/e2e/screenshots/`
5. Reference hashes at `templates/default/tests/e2e/reference-hashes.json`

First run saves the baseline. Subsequent runs compare and fail on mismatch.

## TUI testing notes

The `ks` installer is a terminal UI (ratatui). It is not a line-oriented CLI.
When testing the TUI interactively over SSH, keep these points in mind.

### Driving the TUI over SSH

```bash
ssh -tt -i .test-iso-dev-key -p 12260 keystone@localhost ks
```

The `-tt` forces a remote PTY. Without it, `ks` fails with
`Error: No such device or address (os error 6)` because it cannot set up
terminal raw mode.

### Key sequences

Use carriage return (`\r`) not line feed (`\n`) when scripting. `\n` may
behave like navigation instead of submit.

The template fixture has two hosts (`laptop`, `server-ocean`) and one virtio
disk. The installer screens are:

1. **Host selection** — first item (`laptop`) is focused by default. Press Enter.
2. **Disk selection** — only one disk. Press Enter.
3. **Confirmation** — warns about data erasure. Press Enter to proceed.

### Terminal environment

If the VM reports `Cannot find terminfo entry for 'xterm-ghostty'`, set
`TERM=xterm-256color` before launching `ks`:

```bash
TERM=xterm-256color ks
```

### Automated TUI driving

For scripted testing, `ks install --host laptop` is preferred over driving
the TUI with `expect` or FIFO-based key injection. The headless install
reuses the same code paths (host selection, disk discovery, disko,
nixos-install, handoff) without needing a PTY.

If TUI-level regression testing is needed (verifying screen rendering,
navigation, key bindings), use `ks --screenshot <screen>` which renders a
single screen to stdout without entering raw mode:

```bash
ks --screenshot welcome
ks --screenshot create-config
ks --screenshot hosts
```

### Do not trust the TUI alone

The installer screen shows streaming command output, but it is not the best
source of truth for install state. Use separate SSH sessions to check:

- `/tmp/keystone-install-repo` — the writable install repo (hardware config, commits)
- `/mnt/nix/var/nix/profiles/system` — whether nixos-install landed the system
- `/mnt/home/<user>/.keystone/repos/` — whether the handoff completed
- `free -h` and `ps` — whether the VM is healthy or OOM

See `CONTRIBUTOR.md` for detailed debugging commands.
