# Agent guide for this keystone-config repo

This repository was scaffolded from
[`github:ncrmro/keystone#default`](https://github.com/ncrmro/keystone).
It declares one Keystone "system" — a fleet of hosts configured as a whole —
and is consumed by `ks update`, `nixos-rebuild`, and the Keystone installer.

If you've just landed here, read [`docs/keystone/onboarding.md`](docs/keystone/onboarding.md)
first. It is the canonical walkthrough; everything below is the short version
for orientation.

## What lives where

- `flake.nix` — the only file most changes touch. Owner identity, defaults,
  shared modules, `keystoneServices`, and the `hosts` inventory.
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
