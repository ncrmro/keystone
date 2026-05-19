# Agent guide for this keystone-config repo

This repository was scaffolded from
[`github:ncrmro/keystone#default`](https://github.com/ncrmro/keystone).
It declares one Keystone "system" — a fleet of hosts configured as a whole —
and is consumed by `ks update`, `nixos-rebuild`, and the Keystone installer.

If you've just landed here, read [`docs/keystone/onboarding.md`](docs/keystone/onboarding.md)
first. It is the canonical walkthrough; everything below is the short version
for orientation.

## Docs in this repo

These docs are owned by this repo, safe to edit, and worth reading **before**
reasoning from scratch when a question falls in their scope:

- [`docs/keystone/onboarding.md`](docs/keystone/onboarding.md) — progressive
  walkthrough from `nix flake new` to a fully secured first host. Numbered
  steps, each with Goal → Edit → Run → Verify → If-it-fails.
- [`docs/keystone/flake.md`](docs/keystone/flake.md) — reference for
  `keystone.lib.mkSystemFlake`: every argument it accepts (`admin`,
  `defaults`, `hostsRoot`, `shared.*`, `keystoneServices`, `hosts`) and every
  output it produces (`nixosConfigurations`, `homeConfigurations`,
  `packages.<system>.iso`, …).
- [`docs/keystone/build-and-burn.md`](docs/keystone/build-and-burn.md) — build
  the installer ISO and write it to USB. Cross-platform notes for Linux,
  macOS, and Windows drivers.
- [`docs/keystone/github-token.md`](docs/keystone/github-token.md) — set up
  an agenix-encrypted GitHub PAT so the host doesn't hit the 60/hr anonymous
  rate-limit during `ks update`.
- [`docs/keystone/system-agent-prompts.md`](docs/keystone/system-agent-prompts.md)
  — the user-facing prompt library. When a user pastes one of these, the
  intent and placeholders tell you which other doc to consult.
- [`secrets/README.md`](secrets/README.md) — recipients model, encrypt/decrypt
  flow, naming conventions, and what *not* to commit to `secrets/`.

## What lives where

- `flake.nix` — the only file most changes touch. A single call to
  `keystone.lib.mkSystemFlake { admin; defaults; hostsRoot; shared;
  keystoneServices; hosts; }` that expands the inventory into
  `nixosConfigurations`, `homeConfigurations`, and `packages.<system>.iso`.
  Argument and output reference: [`docs/keystone/flake.md`](docs/keystone/flake.md).
  Helper source: `keystone/lib/templates.nix`.
- `hosts/<name>/configuration.nix` — host-only overrides. For Linux hosts
  (`laptop` / `workstation` / `server`) this is a **NixOS module**. For
  macOS hosts (`kind = "macbook"`) it's a **Home Manager module** — no NixOS
  system, no agenix, just user-scope packages and dotfiles. The file in
  `hosts/macbook/configuration.nix` documents the boundary.
- `hosts/<name>/hardware.nix` — disk IDs, hostId, machine-specific knobs.
  Linux hosts only; macbook has no hardware.nix.
- `secrets/*.age` + `secrets.nix` — agenix-encrypted secrets and their
  recipient lists. `secrets/` is empty by default; you only populate it from
  Step 8 of onboarding onward.
- `docs/keystone/` — the onboarding spine, the build-and-burn reference, the
  GitHub-PAT setup. Owned by this repo; edit freely.
- `bin/` — repo-local scripts. The shipped `bin/test-iso` is keystone's
  installer-ISO smoke test.

## Commands that matter

```bash
nix flake check --no-build       # cheap sanity: outputs evaluate
nix build .#iso                  # build the installer ISO (one artifact for all Linux hosts)
sudo nixos-rebuild switch --flake .#<host>   # local rebuild on a configured host
ks update                        # canonical: pull keystone, relock, build, deploy
```

The ISO is a **single artifact** that bakes in installer targets for every
Linux host in `flake.nix`. There is no per-host ISO output. Specifically:

- `nix build .#iso` — correct.
- `nix build .#nixosConfigurations.<host>.config.system.build.isoImage` — does
  not exist on Keystone hosts. They don't include `installation-cd-minimal.nix`.

## Conventions worth knowing before you edit

**Linux host configs are NixOS modules.** When you wire up shell init,
environment variables, services, etc. in `hosts/<name>/configuration.nix` for
a Linux host, use NixOS option names:

- `programs.zsh.interactiveShellInit` (or `environment.interactiveShellInit`
  for shell-agnostic) — **not** `programs.zsh.initExtra`. The latter is a Home
  Manager option and won't evaluate inside the NixOS host module.
- Same for bash: `programs.bash.interactiveShellInit`.

Home Manager options live in user modules (set via `shared.userModules` or
`shared.desktopUserModules` in `flake.nix`), not in `hosts/*/configuration.nix`.

**Secrets never land in the Nix store.** Agenix decrypts at activation time
into `/run/agenix/<name>` (root-owned by default; set `owner`/`mode` to widen
access). Read them at runtime — for example, a shell-init hook that sources
the file into the env — rather than via `home.sessionVariables` or
`nix.settings.access-tokens`, both of which embed the value at evaluation time
and end up world-readable in `/nix/store`.

**`agenix` is not a separate flake input.** Keystone's `operating-system`
module already imports `agenix.nixosModules.default`, so `age.secrets.*` is
available on every host with no extra plumbing.

**Don't hand-edit `flake.lock` for non-keystone reasons.** Bumping the
`keystone` input is `nix flake update keystone` (targeted, not bare). `ks
update --lock` does the same thing as part of the full deploy.

## Common asks

- "Add a new host" → declare the entry in `hosts = { ... }` inside `flake.nix`,
  drop a matching `hosts/<name>/configuration.nix` (and `hardware.nix` for
  Linux). Pick a `kind`: `laptop` | `workstation` | `server` | `macbook`.
- "Add a service" → set `keystoneServices.<service>.host = "<host-name>"` in
  `flake.nix`. Keystone validates the host exists and auto-enables both the
  server and any clients on the fleet.
- "Add a package to every machine" → `shared.systemModules` for OS-wide,
  `shared.userModules` for per-user, `shared.desktopUserModules` for GUI hosts
  only. Comments inside `flake.nix` show each.
- "Set up GitHub auth so I stop hitting 403s" → follow
  [`docs/keystone/github-token.md`](docs/keystone/github-token.md).

## `ks doctor` — what it does and doesn't check

`ks doctor` is the canonical first-pass health check. It currently reports on:

- NixOS generation in use
- Failed systemd units
- Disk usage
- `flake.lock` age (drift signal)
- Ollama diagnostics
- Per-host fleet health (other hosts' generations via SSH probe)
- Agent service health and current task status
- Desktop-trigger prerequisites: polkit agent, notification daemon,
  `pkexec` setuid bit

**It does NOT currently report on the host's security posture.** When a
user asks "is this host secure" or runs the "diagnose system health"
prompt, check these separately and surface the gaps explicitly:

- **LUKS unlock method.** What's enrolled to decrypt `rpool`'s LUKS
  container — password, recovery key, TPM, or hardware key (YubiKey /
  FIDO2)? Inspect with `sudo cryptsetup luksDump /dev/<luks>` (list of
  keyslots) and `sudo systemd-cryptenroll /dev/<luks>` (enrolled slot
  types). Default keystone installs ship with a *temporary* `keystone`
  password slot that should be removed once TPM unlock is wired up.
- **TPM unlock state.** Is the TPM keyslot bound to a current PCR set and
  actually unlocking on boot? `sudo systemd-cryptenroll --tpm2-device=auto
  /dev/<luks>` shows enrollment; `journalctl -b -u systemd-cryptsetup@*`
  shows boot-time unlock attempts. If TPM enrollment is present but boot
  still prompts for a passphrase, the PCR binding is likely stale.
- **Secure Boot.** `bootctl status` for general boot state; `sbctl status`
  for whether keys are enrolled and which binaries are signed. Lanzaboote
  reports here too.
- **SSH agent.** Is `ssh-agent` running for the current session and does
  it hold the expected identities? `ssh-add -L` prints loaded public keys;
  empty output means no keys loaded.
- **Fingerprint reader.** Is there reader hardware that just isn't enrolled
  yet — a common state on fresh installs? Check `lsusb | rg -i fingerprint`
  and `fprintd-list "$USER"` (requires `loginctl enable-linger`). If a
  reader is present but `fprintd-list` returns no enrollments, walk the
  user through `fprintd-enroll`.

Treat these as a security-posture supplement to `ks doctor`'s output, not
a replacement.

## Verification expectations

Before you call a change done, at minimum:

1. `nix flake check --no-build` exits 0.
2. If the change targets a specific host, `sudo nixos-rebuild dry-activate --flake .#<host>`
   succeeds.
3. If the change is ISO-related, `nix build .#iso` produces a file in
   `result/iso/` of at least several hundred MB.

For full deploy validation, run `ks update` and observe the cycle complete.

## Where Keystone itself lives

The platform — modules, packages, the `ks` CLI — is at
[`ncrmro/keystone`](https://github.com/ncrmro/keystone). When you need to
understand *why* an option exists or what a module wires up, that's where to
look:

- `keystone/modules/` — NixOS modules (OS, server, desktop, agents)
- `keystone/modules/terminal/` — Home Manager terminal modules
- `keystone/lib/templates.nix` — the `mkSystemFlake` helper that turns your
  `flake.nix` into `nixosConfigurations` / `homeConfigurations` / `packages.iso`
- `keystone/packages/ks/` — the `ks` CLI source
- `keystone/conventions/` — project-wide conventions referenced from module comments
