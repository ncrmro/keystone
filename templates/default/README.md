# keystone-config

This repository was generated from the Keystone flake template:

```bash
nix flake new -t github:ncrmro/keystone keystone-config
cd keystone-config
```

Most keystone config changes happen in the `flake.nix`, read more about how
it works in [`docs/keystone/flake.md`](docs/keystone/flake.md).

## After making changes

```bash
# Update the current host
ks update

# Update other hosts
ks update HOST1,HOST2
```

## Ask an AI assistant

This repo ships an [`AGENTS.md`](AGENTS.md) that any AI coding agent (Claude
Code, Codex, Gemini CLI, opencode, etc.) reads automatically when you open
the directory. Try one of these prompts:

**Bootstrap a new host:**
> Read `AGENTS.md` and `docs/keystone/onboarding.md`. Ask me a few
> clarifying questions about my setup (the hosts I want, where my SSH key
> lives, what OS I'm driving from), then walk me through the first three
> steps, including the exact edits to `flake.nix`.

**Learn more about how the flake is wired:**
> Read `AGENTS.md` and `docs/keystone/flake.md`. Summarize how
> `mkSystemFlake` turns my inventory into flake outputs, and call out
> arguments I'm not using yet that might be relevant for my fleet.

**Add an agenix-encrypted secret:**
> Read `AGENTS.md` and `docs/keystone/github-token.md`. I want to add an
> agenix-encrypted `<name>` secret consumed by the `<host>` host. Walk me
> through encrypting it, declaring `age.secrets.*`, and reading it at
> runtime without leaking through the Nix store.

## Quick start

Open `docs/keystone/onboarding.md`.

If you'd rather see the existing `TODO:` markers up front:

```bash
grep -RIn "TODO:" flake.nix hosts/
```

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
- [`docs/keystone/flake.md`](docs/keystone/flake.md) — reference for
  `keystone.lib.mkSystemFlake`: every argument it accepts and every output
  it produces.
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
