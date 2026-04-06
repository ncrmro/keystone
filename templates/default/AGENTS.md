# Keystone config repo

This repository manages NixOS and macOS system configurations using
[Keystone](https://github.com/ncrmro/keystone), a NixOS-based infrastructure
platform. The `flake.nix` is the single entry point — it calls
`keystone.lib.mkSystemFlake` which expands a host inventory into full
`nixosConfigurations`, `homeConfigurations`, and an installer ISO.

## Architecture

### flake.nix structure

```nix
keystone.lib.mkSystemFlake {
  admin = { username, fullName, email, initialPassword, sshKeys };
  defaults = { timeZone };
  shared = { userModules, systemModules };
  keystoneServices = { git.host, mail.host, ... };
  hostsRoot = ./hosts;
  hosts = {
    <name> = { kind = "laptop" | "workstation" | "server" | "macbook"; ... };
  };
}
```

- **`admin`** — the system administrator. `username` is the login name on all
  hosts. `sshKeys` are baked into the installer ISO for remote access. All other
  fields (`fullName`, `email`, `initialPassword`, `terminal.enable`, etc.) map
  directly to `keystone.os.admin` on each NixOS host.
- **`hosts`** — each entry declares a machine. The `kind` field selects the
  archetype: `laptop` (ext4, desktop), `workstation` (ZFS, desktop), `server`
  (ZFS, no desktop), `macbook` (home-manager only).
- **`shared.userModules`** — home-manager modules applied to every user on every
  host. Use for terminal tools, shell config, and packages that follow your login.
- **`shared.systemModules`** — NixOS modules applied to every Linux host. Use for
  system-wide packages, services, or kernel config.
- **`keystoneServices`** — declares which host runs each infrastructure service.
  Keystone validates host references and auto-enables the service on the matching
  machine.

### Host directories

Each Linux host can have a directory under `hosts/<name>/` with:

- `hardware.nix` — hardware scan output (`nixos-generate-config`), disk IDs,
  `networking.hostId`, storage device paths
- `configuration.nix` — host-specific NixOS overrides

VPS-style servers can omit both files. macOS hosts use `configuration.nix` for
home-manager overrides only.

## Common commands

### Building and deploying

```bash
ks build                          # build current host (no deploy, no sudo)
ks build <hostname>               # build a specific host
ks update --lock <hostname>       # full deploy: lock, build, push, switch
ks update --dev                   # deploy home-manager profiles only (dev mode)
ks doctor                         # diagnose system health
```

`ks` discovers this repo via `$NIXOS_CONFIG_DIR`, the git root, or `~/nixos-config`.

### Building the installer ISO

```bash
nix build .#packages.x86_64-linux.iso -o installer-iso
```

Validate in a VM:

```bash
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm \
  -bios $(nix build nixpkgs#OVMF.fd --print-out-paths --no-link)/FV/OVMF.fd \
  -cdrom installer-iso/iso/*.iso
```

Flash to USB:

```bash
sudo dd if=installer-iso/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### Fresh install from ISO

```bash
nixos-anywhere --flake .#<hostname> root@<installer-ip>
```

### Updating keystone

```bash
nix flake update keystone         # update keystone input only — NEVER bare nix flake update
git add flake.lock && git commit -m "chore(deps): update keystone"
```

## How to add packages

### User packages (follow your login)

Add to `shared.userModules` in `flake.nix`:

```nix
shared.userModules = [
  ({ pkgs, ... }: {
    home.packages = with pkgs; [
      fd
      ripgrep
      jq
    ];
  })
];
```

### System packages (all users, root-owned)

Add to `shared.systemModules` in `flake.nix`:

```nix
shared.systemModules = [
  ({ pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      btop
      lsof
    ];
  })
];
```

### Host-specific packages

Add a module to the host's `modules` list in `flake.nix` or in the host's
`configuration.nix`:

```nix
# In flake.nix
hosts.laptop = {
  kind = "laptop";
  modules = [
    ({ pkgs, ... }: { environment.systemPackages = [ pkgs.steam ]; })
  ];
};

# Or in hosts/laptop/configuration.nix
{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.steam ];
}
```

## How to enable services

### Keystone infrastructure services

Declare in `keystoneServices` to auto-enable on the target host:

```nix
keystoneServices = {
  git.host = "server-ocean";
  mail.host = "server-ocean";
};
```

### Standard NixOS services

Add to `shared.systemModules` or a host's `configuration.nix`:

```nix
# All hosts
shared.systemModules = [
  { services.tailscale.enable = true; }
];

# Single host
hosts.server-ocean = {
  kind = "server";
  config.services.openssh.enable = true;
};
```

### Per-host in configuration.nix

```nix
# hosts/server-ocean/configuration.nix
{ ... }: {
  services.postgresql.enable = true;
  services.nginx.enable = true;
}
```

## Adding a new host

1. Add the host to `hosts` in `flake.nix`:
   ```nix
   hosts.new-server = {
     kind = "server";
     hostname = "new-server";
   };
   ```
2. Create `hosts/new-server/hardware.nix` with disk IDs and `networking.hostId`
   (generate with `head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '`)
3. Optionally create `hosts/new-server/configuration.nix` for host-specific config
4. Build: `ks build new-server`
5. Deploy: `nixos-anywhere --flake .#new-server root@<ip>`

## Keystone module reference

| Module area | What it provides |
|-------------|-----------------|
| `keystone.os` | Storage (ZFS/ext4), Secure Boot, TPM, users, SSH |
| `keystone.terminal` | Helix editor, zsh, starship, git, AI tools |
| `keystone.desktop` | Hyprland, audio, bluetooth, greetd |
| `keystone.services` | Service registry (git, mail, immich, etc.) |
| `keystone.keys` | SSH public key registry |
