# Keystone

@CONTRIBUTOR.md — development workflow, verification commands, and deployment flow

Keystone is a NixOS-based self-sovereign infrastructure platform for deploying secure,
encrypted infrastructure on any hardware. It provides declarative modules for OS
configuration, desktop environments, terminal tooling, and server services.

## Fleet model

A keystone system is a **fleet of hosts configured as a whole** in a single
git-committed consumer flake (e.g., `nixos-config` or `keystone-config`).
Enabling a service wires up both the server and its clients across the fleet.
A typical deployment:

- **Workstation** — primary desktop, GPU, agents, full development environment
- **Laptop** — thin client, remotes into workstation via SSH or Eternal Terminal
- **Server/NAS** — headless services (Forgejo, Grafana, Immich, mail, DNS, monitoring)
- **Offsite/VPS** — backup target, public-facing reverse proxy, or Headscale coordinator

`ks update --lock` deploys the current host by default. Pass a comma-separated
list to deploy multiple: `ks update --lock ocean,mercury`.

## Host kinds

`mkSystemFlake` dispatches each host through a `kind` to one of four builders:

- `laptop` — ext4 single-disk desktop, UEFI + secureBoot + TPM2.
- `workstation` — ZFS desktop with kernel pinning, UEFI + secureBoot + TPM2.
- `server` — baremetal ZFS server, optional data pool, UEFI + secureBoot + TPM2.
- `server-vm` — cloud / hosted-VM server. UEFI is the default and recommended
  path (grub-in-ESP with `efiInstallAsRemovable = true` for cloud-image
  friendliness); pass `bios = true` to opt into legacy grub-BIOS for old
  hardware or hobby/legacy VMs. Keystone does not install or touch the
  bootloader on `server-vm` hosts — it only writes the grub config the
  provider's firmware already manages. SecureBoot, TPM, ZFS root, and
  lm_sensors are off by default; opt into any of them per-host.

## Modules

- `modules/os/` — Core OS: storage, Secure Boot, TPM, users, SSH, agents, containers, Tailscale
- `modules/os/agents/` — Autonomous agent service accounts: task loop, scheduler, desktop, mail
- `modules/terminal/` — Home-manager terminal: shell, editor, AI tools, mail, calendar, DeepWork
- `modules/desktop/` — Hyprland desktop environment: theming, keybindings, components
- `modules/server/` — Server services: DNS, mail, monitoring, Forgejo, Grafana, Immich, Vaultwarden

## Packages

- `packages/ks/` — Keystone CLI/TUI: build, deploy, notifications, tasks, projects, doctor
- `packages/fetch-email-source/` — Email notification fetcher (himalaya)
- `packages/fetch-github-sources/` — GitHub notification fetcher (gh API)
- `packages/fetch-forgejo-sources/` — Forgejo notification fetcher (curl)
- `packages/keystone-ha/` — Home-assistant integration

## Flake Exports

### NixOS Modules (`keystone.nixosModules.*`)

| Module | Description |
|---|---|
| `operating-system` | Core OS — storage, Secure Boot, TPM, users, agents (includes disko + lanzaboote) |
| `server` | Server services (includes domain) |
| `desktop` | Hyprland desktop environment |
| `binaryCacheClient` | Attic binary cache client |
| `hardwareKey` | YubiKey/FIDO2 support |
| `isoInstaller` | Bootable installer |
| `experimental` | Experimental feature flag (`keystone.experimental`) |
| `domain`, `hosts`, `repos`, `services`, `keys` | Shared options modules |
| `headscale-dns` | Consume server DNS records on headscale host |

### Home-Manager Modules (`keystone.homeModules.*`)

`terminal`, `desktop`, `desktopHyprland`, `notes`

### Overlay (`pkgs.keystone.*`)

`claude-code`, `gemini-cli`, `codex`, `opencode`, `deepwork`, `keystone-deepwork-jobs`,
`keystone-conventions`, `chrome-devtools-mcp`, `grafana-mcp`, `google-chrome`, `ghostty`,
`yazi`, `himalaya`, `calendula`, `cardamum`, `comodoro`, `cfait`, `agenix`, `slidev`

## Important Notes

- ZFS pool is **always** named `rpool`
- The `operating-system` module includes disko and lanzaboote — no separate import needed
- Terminal and desktop modules are home-manager based, not NixOS system modules
- `keystone.repos` auto-populates from flake inputs; `keystone.development` enables local checkout paths
- `keystone.experimental` (default `false`) gates experimental features. Defined in `modules/shared/experimental.nix`.

## Keystone Config Repo

The **keystone config repo** is `ks-config` — the consumer flake that imports keystone
modules and declares per-host/per-user configuration. Keystone-managed repos live
under `~/repos/OWNER/REPO/`; `~/.keystone/repos/OWNER/REPO/` is legacy fallback only.

## Pull request workflow

PR mechanics — draft → Copilot review → merge queue, plus issue and
milestone linkage — live in
[`CONTRIBUTOR.md` § Pull request workflow](CONTRIBUTOR.md#pull-request-workflow).
Agents follow that section for every PR; the canonical source is the
`process.pr-shepherding` skill convention.
