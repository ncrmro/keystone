# Keystone

Own your infrastructure. Keystone turns one or more machines into a unified,
self-hosted system — encrypted storage, integrated services, and a fully configurable
foundation that enables capabilities like autonomous AI agents operating with real
system identity. Add users for everyone in your household, or run it solo.

**[Get Started](docs/installation.md)** · **[Documentation](https://ncrmro.github.io/keystone/)**

<!-- TODO: hero screenshot of TUI or dashboard -->

---

## Your Data, Your Hardware

Keystone installs on any x86 machine via USB. The setup TUI handles disk encryption,
user creation, and service configuration — no config files required.

- Full disk encryption with TPM2 auto-unlock
- Secure Boot with custom key enrollment
- ZFS storage with snapshots and compression

[Installation Guide](docs/installation.md) · [TPM Enrollment](docs/tpm-enrollment.md)

<!-- TODO: TUI welcome/setup screenshot -->

## Self-Hosted Services

Enable services with a single toggle. Keystone auto-configures TLS certificates,
reverse proxy, and DNS for each one.

| Service | What it replaces |
|---------|-----------------|
| Immich | Google Photos |
| Forgejo | GitHub |
| Vaultwarden | 1Password |
| Stalwart | Gmail |
| AdGuard | Pi-hole |
| Headscale | Tailscale control |
| Grafana + Prometheus + Loki | Datadog |
| Miniflux | Feedly |
| Attic | Cachix |
| SeaweedFS | S3 |

[Server Documentation](docs/server.md)

<!-- TODO: services screenshot -->

## Desktop & Terminal

A complete development environment — terminal or full desktop.

**Terminal**: Zsh, Helix editor, Zellij multiplexer, Git with SSH signing, AI coding tools

**Desktop**: Hyprland compositor, 15 themes, app launcher, clipboard history, screenshot tools

[Terminal](docs/terminal.md) · [Personal Info Management](docs/personal-info-management.md)

## OS Agents

Autonomous user accounts that run on your system with their own identity,
email, git workspace, and task queue. Agents fetch issues, write code, open PRs,
and process documents — all on your hardware.

[Agent Documentation](docs/os-agents.md)

---

## Getting Started

### USB Install (Recommended)

Build the installer ISO, boot on target hardware, and follow the TUI.

```bash
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

[Full Installation Guide](docs/installation.md)

### For NixOS Users

Keystone is a set of NixOS and home-manager modules. Use it as a flake input
for full control over your configuration.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs = { nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        keystone.nixosModules.operating-system
        {
          networking.hostId = "deadbeef";
          keystone.os = {
            enable = true;
            storage.devices = [ "/dev/disk/by-id/nvme-..." ];
            users.admin = {
              fullName = "Admin";
              extraGroups = [ "wheel" ];
              authorizedKeys = [ "ssh-ed25519 ..." ];
            };
          };
        }
      ];
    };
  };
}
```

[Module Reference](docs/index.md) · [Examples](docs/examples.md)

## Development

```bash
make build-vm-terminal    # SSH into terminal VM
make build-vm-desktop     # Hyprland desktop VM
make test                 # Run test suite
```

[VM Testing](docs/testing-vm.md) · [Testing Procedures](docs/testing-procedure.md)

## License

[MIT](LICENSE)
