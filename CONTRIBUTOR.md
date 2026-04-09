# Contributor guide

## End-to-end VM install testing

This repo's installer work is easiest to validate against a real consumer repo
that uses the current Keystone checkout. The fastest loop is:

1. Rebuild the ISO from the consumer repo in dev mode.
2. Boot a fresh VM from that ISO.
3. Drive the real `ks` installer TUI.
4. Watch the staged repo in `/tmp` and the target root at `/mnt`.
5. Reboot from the installed disk and validate first boot.

The TUI is useful for phase changes, but it is too noisy to use as the only
source of truth.

## Typical ISO build loop

From a consumer repo such as `~/repos/noah-horton/keystone-config`:

```bash
./bin/test-iso --build-only --dev
```

That builds the installer ISO from the current Keystone working tree snapshot.
In `--dev` mode, the template harness prefers a repo-local gitignored SSH key
at `.test-iso-dev-key` and generates it automatically if missing. The same
development key is also handed off into the installed user's
`~/.ssh/authorized_keys` so reboot testing can keep using the same identity.

Before each clean install run, remove the old test disk:

```bash
rm -f .test-iso-disk.raw
```

Then boot a fresh headless VM:

```bash
./bin/test-iso --no-build --headless -p 12251
```

Headful mode is the default:

```bash
./bin/test-iso --no-build
```

Useful flags:

```bash
./bin/test-iso --build-only --dev
./bin/test-iso --no-build --headless -p 12251
./bin/test-iso --no-build -p 12251
```

When `--dev` created the repo-local test key, use it for live ISO SSH:

```bash
ssh -i .test-iso-dev-key -tt -p 12251 -o StrictHostKeyChecking=no noah@localhost
```

## Driving the installer TUI

SSH into the live installer:

```bash
ssh -tt -p 12251 -o StrictHostKeyChecking=no noah@localhost
```

If your terminal reports `xterm-ghostty` or another terminfo mismatch, set:

```bash
export TERM=xterm
ks
```

When a human is driving the TUI directly, use normal Enter/arrow keys.

When an agent or script is driving the TUI through a PTY, send carriage return
(`\r`), not line feed (`\n`). `\n` often behaves like navigation instead of
submit.

The current installer phases are:

1. `disko`
2. hardware capture via `nixos-generate-config --show-hardware-config`
3. local install commit
4. `nixos-install`

## Do not trust the TUI alone

The installer screen is an alternate-screen terminal UI with streaming command
output. It is useful for:

- seeing the current phase
- spotting the exact command being run
- seeing obvious fatal errors

It is not good for:

- understanding whether the staged repo was updated correctly
- knowing whether the target system has actually landed in `/mnt`
- monitoring memory, swap, and long-running Nix builds

Use separate SSH sessions for those checks.

## Watch the staged repo

The writable install repo lives at:

```bash
/tmp/keystone-install-repo
```

Useful checks while the TUI is running:

```bash
git -C /tmp/keystone-install-repo log --oneline -2
ls /tmp/keystone-install-repo/hosts/laptop
sed -n '1,160p' /tmp/keystone-install-repo/hosts/laptop/hardware.nix
sed -n '1,160p' /tmp/keystone-install-repo/hosts/laptop/hardware-generated.nix
git -C /tmp/keystone-install-repo status --short
```

What to expect:

- Before phase 2: only the installer snapshot commit is present.
- After phase 2: `hardware-generated.nix` exists.
- After phase 3: a new local install commit exists on top of the snapshot.

If `hardware-generated.nix` exists, verify that it only contains hardware facts
such as:

- `imports`
- kernel modules
- host platform

It must not redefine storage-owned options such as:

- `fileSystems.*`
- `swapDevices`
- `boot.initrd.luks.devices.*`

Keystone storage owns those.

## Watch `/mnt`, not just the TUI

The least noisy signal for actual install progress is the target root:

```bash
ls -al /mnt
readlink -f /mnt/nix/var/nix/profiles/system
ls -ld /mnt/home/noah/.keystone/repos/noah/keystone-config
cat /mnt/etc/keystone/system-flake
```

Interpretation:

- No system profile yet:
  - `nixos-install` is still running, or it failed before landing the system.
- System profile present:
  - the NixOS install finished.
- Installed repo present under `/mnt/home/<user>/.keystone/repos/<owner>/keystone-config`:
  - the Keystone handoff finished.
- `/mnt/etc/keystone/system-flake` present:
  - the system flake pointer was written.

The expected final path is:

```bash
/mnt/home/<user>/.keystone/repos/<owner>/keystone-config
```

With current defaults:

- `owner` defaults from `admin.username`
- `repoName` defaults to `keystone-config`

## Monitor install performance

Use side sessions to understand whether the VM is healthy or just stuck.

### Active install processes

```bash
ps -eo pid,ppid,etime,%cpu,%mem,cmd --sort=-%cpu | \
  grep -E '(nixos-install|nix --extra-experimental-features|rustc|cargo|cc|clang|ld|c\+\+)' | \
  grep -v grep | \
  head -n 30
```

What to look for:

- one active `nix` worker under `nixos-install`
- `rustc` or `cargo` children when a real local Rust build is happening
- a builder shell under the `nix` worker when a derivation is actively building

### Memory and swap

```bash
free -h
swapon --show --bytes --noheadings
```

Rules of thumb:

- Rising RAM with zero swap can still be fine.
- Rising swap on zram is expected under real build load.
- The dangerous state is falling free memory, growing swap, and then an abrupt
  `nixos-install` exit.

### Recent boot and sudo activity

```bash
journalctl -b --no-pager -n 80
```

Useful signals:

- `sudo ... nixos-generate-config --show-hardware-config`
- `sudo ... nixos-install`
- `pam_unix(sudo:session): session closed for user root`

If the sudo session closes and `/mnt` is still mostly empty, the install failed
before landing the system.

## Cache observations during install

The TUI is still useful for cache hints because it shows:

- `copying path ... from https://cache.nixos.org`
- `copying path ... from https://ks-systems.cachix.org`
- `building ...`

Practical guidance:

- treat `copying path ...` as a cache hit
- treat `building ...` as a cache miss for that exact graph
- verify heavy Rust stacks separately if install time matters

The most reliable measure is not the TUI itself, but whether the VM finishes
without OOM and whether `rustc`/`cargo` processes actually appear.

## Reboot and installed-disk testing

A successful install is not the end of the test. Reboot from the installed disk
and validate first boot separately.

Important details:

- SSH may never come up if the VM is waiting at a LUKS prompt.
- For current template defaults, the disk unlock password is `keystone`.
- User login credentials come from the consumer config, not the live ISO.

For reboot debugging, prefer one of:

- headful QEMU so you can watch the console
- serial logging
- explicit disk-only boot harnesses

Do not assume a failed SSH check means the installed system failed to boot. It
may simply be waiting for disk unlock.

## Recommended debugging order

When an end-to-end run fails, use this order:

1. Confirm the current TUI phase.
2. Check `/tmp/keystone-install-repo` for `hardware-generated.nix` and the
   local install commit.
3. Check whether `/mnt/nix/var/nix/profiles/system` exists.
4. Check whether the installed repo handoff landed in `/mnt/home/.../.keystone`.
5. Check `free -h`, `swapon`, and the active `nix` worker.
6. Only then dig into the TUI noise or rerun `nixos-install` manually for
   clearer stderr.

Manual reruns are for diagnosis. The TUI path is the real product path and must
be the thing that succeeds.
