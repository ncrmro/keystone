# Keystone

A mission-focused operating system and suite of tools for owning your
infrastructure. Declare a fleet of hosts — workstation, laptop, server,
offsite — in one git-committed flake. Bring them up with encrypted storage,
secure boot, integrated services, and autonomous AI agents running under real
system identity.

**[Get started](docs/keystone/onboarding.md)** ·
**[Modules](docs/index.md)** ·
**[`ks` CLI](docs/ks.md)** ·
**[Comparison](docs/comparison.md)**

---

## Where Keystone runs

Keystone is built on NixOS and deployable in three shapes:

- **Linux (bare metal, primary)** — workstations, laptops, servers. Full
  ownership of the boot chain.
- **macOS via `nix-darwin`** — in flight. Same terminal, desktop tooling, and
  OS-agent identity model on a macOS host you already use for other reasons.
- **Windows via WSL** — bring the keystone terminal and dev environment to a
  machine whose firmware you don't own.

## V1 — bare-metal install, the most secure path

V1 focuses on getting Keystone onto off-the-shelf hardware in the most secure
way possible: Lanzaboote Secure Boot, LUKS + TPM2 auto-unlock, ZFS on `rpool`,
fingerprint reader where available.

Hardware classes targeted for V1:

- **Framework** — Laptop 13, Laptop 16
- **DIY desktops** — AMD or Intel, NVMe + ZFS
- **Dell** — Latitude, XPS, Precision (TPM2-equipped)
- **Lenovo** — ThinkPad T / X / P series
- **Intel Macs** — late-2018+, standard UEFI
- **Apple Silicon via Asahi Linux** — M1, M2 today; M3 as Asahi support matures

Install flow: USB ISO → installer TUI → encrypt disk → first-boot TPM
enrollment → deploy the fleet flake with `ks update --lock`.

[Installation guide](docs/keystone/onboarding.md) ·
[OS installer reference](docs/keystone/os-installer.md)

## Services you'd otherwise pay for

Enable one with a toggle; Keystone auto-wires TLS, reverse proxy, and DNS.

| Service                     | Replaces          |
| --------------------------- | ----------------- |
| Immich                      | Google Photos     |
| Forgejo                     | GitHub            |
| Vaultwarden                 | 1Password         |
| Stalwart                    | Gmail             |
| AdGuard                     | Pi-hole           |
| Headscale                   | Tailscale control |
| Grafana + Prometheus + Loki | Datadog           |
| Miniflux                    | Feedly            |
| Attic                       | Cachix            |
| SeaweedFS                   | S3                |

## Terminal, desktop, and OS agents

- **Terminal** — Zsh + starship, Helix, Zellij, mail (Himalaya), calendar
  (Khal), DeepWork workflows, AI coding tools (Claude Code, Codex, Gemini,
  OpenCode)
- **Desktop** — Hyprland with themes, app launcher, clipboard history,
  screenshot tools
- **OS agents** — service-account user identities with their own mail, git
  workspace, and task queue. They fetch issues, write code, open PRs, and
  process documents under their own UID, on your hardware.

## Contributing

See [`CONTRIBUTOR.md`](CONTRIBUTOR.md) for the development workflow and
[`AGENTS.md`](AGENTS.md) for the agent-oriented map of the repo.

## License

[MIT](LICENSE)
