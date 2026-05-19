# keystone-config

This repository was generated from the Keystone flake template:

```bash
nix flake new -t github:ncrmro/keystone keystone-config
cd keystone-config
```

The starter `flake.nix` is one call to `keystone.lib.mkSystemFlake`: you
declare owner identity, fleet-wide defaults, shared modules, and a `hosts`
inventory, and the helper expands that into the standard flake outputs:

- `nixosConfigurations.<host>` for every Linux host
- `homeConfigurations.<host>` for every macOS (`kind = "macbook"`) host
- `packages.<system>.iso` — one installer ISO covering every Linux host
- `packages.<system>.vm-image-<host>` — direct-boot qcow2 images per host

That keeps `flake.nix` short while still making the important host choices
easy to scan.

## Quick start

Open `docs/keystone/onboarding.md` and follow the numbered steps. Each step
builds on the last, makes one focused change, and ends with a quick verification.
You can stop after Step 2 if you only need a configured flake, after Step 5 if
you only want a running host, or carry on through Step 8 for the full security +
agenix setup.

```bash
$EDITOR docs/keystone/onboarding.md   # or `glow`, `bat`, `cat`…
```

If you'd rather see the existing `TODO:` markers up front:

```bash
grep -RIn "TODO:" flake.nix hosts/
```

## `mkSystemFlake` at a glance

The arguments you'll set in `flake.nix`:

| Argument | Purpose |
|---|---|
| `admin` | Single source of truth for the admin user (`username`, `fullName`, `email`, `initialPassword`, `sshKeys`). Every host inherits this identity. |
| `defaults` | Fleet-wide defaults — `timeZone`, `updateChannel` (`"stable"` or `"unstable"`). |
| `hostsRoot` | Directory containing per-host subdirectories. The template uses `./hosts`. |
| `shared.userModules` | Home Manager modules applied to every user on every host. |
| `shared.systemModules` | NixOS modules applied OS-wide on every host. |
| `shared.desktopUserModules` | Home Manager modules applied per-user on desktop hosts (laptop, workstation) only. |
| `keystoneServices` | Global service → host wiring (`git.host = "server";`, `mail.host = "server";`, …). Keystone validates each `*.host` matches a declared host, then auto-enables both the server and any clients. |
| `hosts` | Attrset of `<name> = { kind = "laptop" \| "workstation" \| "server" \| "macbook"; … };`. Each entry pulls `hosts/<name>/configuration.nix` and (for Linux) `hosts/<name>/hardware.nix` automatically. |

The helper implementation lives at `keystone/lib/templates.nix` if you need
to see exactly how the inventory becomes flake outputs.

## File layout

- `flake.nix` — single `mkSystemFlake` call: owner/defaults, shared module
  hooks, global `keystoneServices`, and the `hosts` inventory
- `hosts/laptop/` — laptop-specific Linux files
- `hosts/server/` — server-specific Linux files
- `hosts/macbook/` — optional macOS Home Manager overrides (no NixOS system)
- `hosts/<name>/hardware.nix` — optional Linux hardware metadata and
  machine-specific module
- `hosts/<name>/configuration.nix` — optional host-only overrides
- `secrets/` and `secrets.nix` — agenix-encrypted secrets (empty until
  Step 8 of onboarding)
- `docs/keystone/` — onboarding walkthrough, GitHub PAT setup, build + burn
  reference. **Edit the docs freely** — they live in your repo, not upstream.

`server` is just an example name. Rename to anything that fits — make sure
the entry in `flake.nix` `hosts = { ... }` and the directory under `hosts/`
match.

## Included docs

- [`docs/keystone/onboarding.md`](docs/keystone/onboarding.md) — progressive
  walkthrough from `nix flake new` to a fully secured first host.
- [`docs/keystone/build-and-burn.md`](docs/keystone/build-and-burn.md) — build
  the installer ISO and write it to USB (Linux + macOS + Windows).
- [`docs/keystone/github-token.md`](docs/keystone/github-token.md) — set up
  an agenix-encrypted GitHub PAT to avoid rate-limit 403s.
- [`AGENTS.md`](AGENTS.md) — short orientation for AI coding agents (Claude
  Code, Codex, Gemini CLI, etc.). Repo shape, NixOS-vs-Home-Manager pitfalls,
  agenix conventions.

## Where to investigate Keystone itself

- Unified host helper implementation: `keystone/lib/templates.nix`
- Keystone admin and user option schema: `keystone/modules/os/default.nix`
- Keystone admin/user synthesis: `keystone/modules/os/users.nix`
- Keystone NixOS modules: `keystone/modules/`
- Keystone terminal Home Manager module: `keystone/modules/terminal/default.nix`
- Keystone desktop Home Manager module: `keystone/modules/desktop/home/default.nix`

## Day-to-day commands after install

```bash
# Update keystone + relock and deploy
ks update

# Just rebuild without pulling new keystone revs
sudo nixos-rebuild switch --flake .#<host>
```
