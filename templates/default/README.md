# keystone-config

This repository was generated from the Keystone flake template:

```bash
nix flake new -t github:ncrmro/keystone keystone-config
cd keystone-config
```

The starter flake defines one shared Keystone system config and a `hosts`
inventory. Keystone expands that inventory into:

- `nixosConfigurations` for Linux hosts
- `homeConfigurations` for macOS hosts

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

## File layout

- `flake.nix` — shared owner/defaults, shared module hooks, global
  `keystoneServices`, and the `hosts` inventory
- `hosts/laptop/` — laptop-specific Linux files
- `hosts/server-ocean/` — server-specific Linux files
- `hosts/macbook/` — optional macOS Home Manager overrides
- `hosts/<name>/hardware.nix` — optional Linux hardware metadata and
  machine-specific module
- `hosts/<name>/configuration.nix` — optional host-only overrides
- `secrets/` and `secrets.nix` — agenix-encrypted secrets (empty until
  Step 8 of onboarding)
- `docs/keystone/` — onboarding walkthrough, GitHub PAT setup, build + burn
  reference. **Edit the docs freely** — they live in your repo, not upstream.

`server-ocean` is just an example name. Rename to anything that fits.

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
