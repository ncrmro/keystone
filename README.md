# Keystone

Own your infrastructure. Keystone turns one or more machines into a unified,
self-hosted system — encrypted storage, integrated services, and a fully configurable
foundation that enables capabilities like autonomous AI agents operating with real
system identity. Add users for everyone in your household, or run it solo.

**[Get Started](docs/os/installation.md)** · **[Documentation](docs/index.md)** · **[OS Comparison](docs/comparison.md)** · **[Agent Platform Comparison](docs/agents/comparison.md)**

<!-- TODO: hero screenshot of TUI or dashboard -->

---

## Your Data, Your Hardware

Keystone installs on any x86 machine via USB. The setup TUI handles disk encryption,
user creation, and service configuration — no config files required.

- Full disk encryption with TPM2 auto-unlock
- Secure Boot with custom key enrollment
- ZFS storage with snapshots and compression

[Installation Guide](docs/os/installation.md) · [TPM Enrollment](docs/os/tpm-enrollment.md)

<!-- TODO: TUI welcome/setup screenshot -->

## Self-Hosted Services

Enable services with a single toggle. Keystone auto-configures TLS certificates,
reverse proxy, and DNS for each one.

| Service | What it replaces |
|---------|-----------------|
| [Immich](https://immich.app) | Google Photos |
| [Forgejo](https://forgejo.org) | GitHub |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | 1Password |
| [Stalwart](https://stalw.art) | Gmail |
| [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) | Pi-hole |
| [Headscale](https://github.com/juanfont/headscale) | Tailscale control |
| [Grafana](https://grafana.com) + [Prometheus](https://prometheus.io) + [Loki](https://grafana.com/oss/loki/) | Datadog |
| [Miniflux](https://miniflux.app) | Feedly |
| [Attic](https://github.com/zhaofengli/attic) | Cachix |
| [SeaweedFS](https://github.com/seaweedfs/seaweedfs) | S3 |

[Server Documentation](docs/os/server.md)

<!-- TODO: services screenshot -->

## Desktop & Terminal

A complete development environment — terminal or full desktop.

**Terminal**: [Zsh](https://www.zsh.org), [Helix](https://helix-editor.com) editor, [Zellij](https://zellij.dev) multiplexer, Git with SSH signing, AI coding tools,
[DeepWork](https://github.com/Unsupervisedcom/deepwork) workflow engine

**Desktop**: [Hyprland](https://hyprland.org) compositor, 15 themes, app launcher, clipboard history, screenshot tools

[Terminal](docs/terminal/terminal.md) · [DeepWork](docs/terminal/deepwork.md) · [Personal Info Management](docs/os/personal-info-management.md) · [Cross-Platform Comparison](docs/comparison.md)

## OS Agents

Autonomous user accounts that run on your system with their own identity,
email, git workspace, and task queue. Agents fetch issues, write code, open PRs,
and process documents — all on your hardware.

[Agent Documentation](docs/agents/os-agents.md)

---

## Getting Started

### USB Install (Recommended)

Build the installer ISO, boot on target hardware, and follow the TUI.

```bash
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

[Full Installation Guide](docs/os/installation.md)

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

[VM Testing](docs/os/testing-vm.md) · [Testing Procedures](docs/os/testing-procedure.md)

## License

[MIT](LICENSE)
