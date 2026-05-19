---
title: Reasoning about your keystone-config
description: How the scaffolded repo is organized, what convention keystone gives you, and where to fall back to vanilla Nix
---

# Reasoning about your keystone-config

This repo is a **consumer flake** for [Keystone](https://github.com/ncrmro/keystone).
Keystone is convention-over-configuration: `mkSystemFlake` gives you a fleet
model (admin identity, host inventory, fleet-wide module hooks, service
wiring), and the rest is regular Nix flakes + NixOS + Home Manager
underneath. You can drop down to plain Nix anywhere the convention doesn't
fit.

The mental model that pays off: **think in scopes**, not in files.

## Scopes

Every keystone-config change lives in one of these scopes. Pick the scope
first; the file follows.

| Scope | Applies to | Where to write it |
|---|---|---|
| **Fleet-wide, system level** | OS-wide on every host | `shared.systemModules` in `flake.nix` |
| **Fleet-wide, user level** | Per-user on every host (Linux + macOS) | `shared.userModules` in `flake.nix` |
| **Desktop-only, user level** | Per-user on `laptop` / `workstation` only | `shared.desktopUserModules` in `flake.nix` |
| **Per-host, system level** | One Linux host's NixOS | `hosts/<name>/configuration.nix` |
| **Per-host, hardware** | One Linux host's disks/firmware/CPU | `hosts/<name>/hardware.nix` |
| **Per-host, user level (macOS)** | A `kind = "macbook"` host | `hosts/<name>/configuration.nix` (Home Manager only) |
| **Shared infra wiring** | A service whose host every other host should know about | `keystoneServices.<service>.host` in `flake.nix` |
| **Secrets** | Anything that mustn't land in the Nix store | `secrets/<name>.age` + `age.secrets.*` declaration |

Two boundaries make the table work:

- **Fleet vs per-host** — does this apply to everything you own, or just one
  machine?
- **System vs user** — does it need root (`environment.*`, `services.*`,
  `networking.*`), or does it live in your home directory (`home.*`,
  `programs.*.enable`)?

If you don't know which side of "system vs user" something belongs on, the
defaults are good: CLI tools and dotfiles → user; daemons and ports →
system.

## NixOS vs Home Manager

Two different module systems handle the two scopes. Keystone wires them up
for you; you pick the option *names* correctly.

- **NixOS modules** run on Linux hosts. Options live under
  `environment.*`, `services.*`, `networking.*`, `users.*`,
  `programs.<name>.enable`, `programs.<name>.<system-knobs>`, …
  Reference: [NixOS options search](https://search.nixos.org/options).
- **Home Manager modules** run per-user. Options live under `home.*`,
  `programs.<name>.<user-knobs>`, `xdg.*`, `wayland.*`, …
  Reference: [Home Manager options](https://nix-community.github.io/home-manager/options.xhtml).

The same `programs.<name>` namespace exists in **both** systems but with
different schemas — `programs.zsh.interactiveShellInit` is NixOS,
`programs.zsh.initExtra` is Home Manager. They look similar; they are not
interchangeable. Compose the right one for the scope you're writing in.

**macOS hosts (`kind = "macbook"`) get only Home Manager.** No NixOS, no
agenix, no system services. See `hosts/macbook/configuration.nix` for the
boundary.

## Where to install programs

Pick the scope, then the right option name.

**A CLI tool I want on every machine I touch:**

```nix
# flake.nix
shared.userModules = [
  ({ pkgs, ... }: {
    home.packages = with pkgs; [ fd ripgrep jq ];
  })
];
```

**A daemon that should run on every host:**

```nix
# flake.nix
shared.systemModules = [
  ({ pkgs, ... }: {
    services.tailscale.enable = true;
    environment.systemPackages = with pkgs; [ tailscale ];
  })
];
```

**A GUI app on desktop hosts only:**

```nix
# flake.nix
shared.desktopUserModules = [
  ({ pkgs, ... }: {
    home.packages = with pkgs; [ obsidian bitwarden-desktop ];
  })
];
```

**A package only on the laptop:**

```nix
# hosts/laptop/configuration.nix  (NixOS — system scope)
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [ wireshark ];
}
```

For user-scope per-host installs, declare a Home Manager module inside
`hosts/<name>/configuration.nix` instead and reach into `home.packages`.
(See `hosts/macbook/configuration.nix` — that's exactly this pattern,
just on macOS where it's the *only* option.)

Looking for a specific package? [search.nixos.org/packages](https://search.nixos.org/packages).

## Convention over configuration: when to escape it

`mkSystemFlake` is just a function that returns a flake attrset. If you
need something it doesn't model, add to its return value directly:

```nix
outputs = { keystone, ... }: keystone.lib.mkSystemFlake {
  # … your normal mkSystemFlake args …
} // {
  # Anything else flake-shaped goes here.
  packages.x86_64-linux.my-custom-tool =
    keystone.inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage ./my-tool.nix { };

  checks.x86_64-linux.my-custom-test = …;
};
```

You can also override `mkSystemFlake`'s inputs (`nixpkgs`, `llm-agents`,
`browser-previews`) by declaring your own flake inputs and using
`keystone.inputs.<name>.follows`. Comments in `flake.nix` show the
canonical examples.

The point: convention covers the 80% case (fleet of hosts, shared identity,
ISO + per-host configs, agenix). The other 20% is plain Nix and you have
full access to it.

## File layout, briefly

- `flake.nix` — single `mkSystemFlake` call: owner/defaults, shared module
  hooks, global `keystoneServices`, and the `hosts` inventory
- `hosts/laptop/`, `hosts/server/`, `hosts/macbook/` — per-host directories
  named after the keys you declare in `hosts = { ... }`
- `hosts/<name>/configuration.nix` — per-host overrides (NixOS for Linux,
  Home Manager for macOS)
- `hosts/<name>/hardware.nix` — Linux hardware metadata (disks, hostId,
  CPU/firmware quirks). Macbook hosts don't have this file.
- `secrets/*.age` + `secrets.nix` — agenix-encrypted secrets and their
  recipient lists; see [`secrets/README.md`](../../secrets/README.md)
- `docs/keystone/` — these docs. Edit freely; they live in your repo, not
  upstream.

`server` is just an example name. Rename to anything that fits — keep the
entry in `flake.nix` `hosts = { ... }` and the directory under `hosts/` in
sync.

## Going deeper into Nix

When the question is "how does this Nix feature work" rather than "how does
keystone use it":

- **Nix language and flakes:** [nix.dev](https://nix.dev) is the friendliest
  starting point. The [Nix manual](https://nix.dev/manual/nix/stable/) is
  the authoritative reference for the CLI and store model.
- **NixOS modules and options:** [NixOS manual](https://nixos.org/manual/nixos/stable/)
  + [options search](https://search.nixos.org/options).
- **Home Manager modules and options:** [Home Manager manual](https://nix-community.github.io/home-manager/)
  + [options reference](https://nix-community.github.io/home-manager/options.xhtml).
- **Packages:** [search.nixos.org/packages](https://search.nixos.org/packages).
- **agenix:** [ryantm/agenix](https://github.com/ryantm/agenix) for the
  recipients/file-encryption model. Keystone's `operating-system` module
  already imports `agenix.nixosModules.default`, so you don't add it as a
  separate flake input.

Keystone's own helper, when you want to see exactly how the inventory
becomes flake outputs:
[`lib/templates.nix`](https://github.com/ncrmro/keystone/blob/main/lib/templates.nix)
in the keystone repo.
