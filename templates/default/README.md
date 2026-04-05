# keystone-config

This repository was generated from the Keystone flake template.

```bash
nix flake new -t github:ncrmro/keystone keystone-config
cd keystone-config
```

The starter flake defines one shared Keystone system config and one `hosts` inventory. Keystone expands that inventory into:

- `nixosConfigurations` for Linux hosts
- `homeConfigurations` for macOS hosts

That keeps `flake.nix` short while still making the important host choices easy to scan.

## Configure the template

Search for `TODO:` in the root flake and host hardware files:

```bash
grep -RIn "TODO:" flake.nix hosts/
```

Fill in:

- `owner.name` in `flake.nix`
- `owner.username` in `flake.nix` if your primary username is not `admin`
- `owner.email` in `flake.nix`
- `defaults.timeZone` in `flake.nix`
- hostnames in `flake.nix` if `laptop`, `server-ocean`, or `macbook` should be renamed
- `system`, `networking.hostId`, and `keystone.os.storage.devices` in Linux `hardware.nix` files

## File layout

- `flake.nix`: shared owner/defaults, shared module hooks, global `keystoneServices`, and the `hosts` inventory
- `hosts/laptop/`: laptop-specific Linux files
- `hosts/server-ocean/`: server-specific Linux files
- `hosts/macbook/`: optional macOS Home Manager overrides
- `hosts/<name>/hardware.nix`: optional Linux hardware metadata and machine-specific module
- `hosts/<name>/configuration.nix`: optional host-only overrides

Linux `hardware.nix` files can export:

- `system`
- `module`

Keystone uses those when present, but VPS-style servers can omit a hardware file entirely.

## Included defaults

The default template includes:

- `laptop`: desktop Linux host
- `server-ocean`: Linux server host
- `macbook`: terminal-only macOS Home Manager host

`server-ocean` is only an example name. Rename it to any hostname that fits your system.

The server host can represent either:

- a VPS with no local hardware file
- a baremetal machine with a generated hardware file

Shared infrastructure placement belongs in the top-level `keystoneServices` block in `flake.nix`, not inside individual host blocks.

## Where to investigate

- Unified host helper implementation: `keystone/lib/templates.nix`
- Keystone admin and user option schema: `keystone/modules/os/default.nix`
- Keystone admin/user synthesis: `keystone/modules/os/users.nix`
- Keystone NixOS modules: `keystone/modules/`
- Keystone terminal Home Manager module: `keystone/modules/terminal/default.nix`
- Keystone desktop Home Manager module: `keystone/modules/desktop/home/default.nix`

## Deploy

Fresh laptop install:

```bash
nixos-anywhere --flake .#laptop root@<installer-ip>
```

Existing laptop host:

```bash
sudo nixos-rebuild switch --flake .#laptop
```

Server host:

```bash
sudo nixos-rebuild switch --flake .#server-ocean
```
