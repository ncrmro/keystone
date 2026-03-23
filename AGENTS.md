# Keystone

Keystone is a NixOS-based self-sovereign infrastructure platform for deploying secure,
encrypted infrastructure on any hardware. It provides declarative modules for OS
configuration, desktop environments, terminal tooling, and server services.

## Module Navigation

| Module | Editing Guide | User-facing Docs |
|--------|--------------|-----------------|
| `modules/os/` | [modules/os/AGENTS.md](modules/os/AGENTS.md) | [docs/os-agents.md](docs/os-agents.md) |
| `modules/os/agents/` | [modules/os/agents/AGENTS.md](modules/os/agents/AGENTS.md) | [docs/agents.md](docs/agents.md) |
| `modules/terminal/` | [modules/terminal/AGENTS.md](modules/terminal/AGENTS.md) | [docs/terminal.md](docs/terminal.md) |
| `modules/desktop/` | [modules/desktop/AGENTS.md](modules/desktop/AGENTS.md) | — |
| `modules/server/` | [modules/server/AGENTS.md](modules/server/AGENTS.md) | [docs/server.md](docs/server.md) |
| `packages/keystone-tui/` | [packages/keystone-tui/AGENTS.md](packages/keystone-tui/AGENTS.md) | — |
| `conventions/` | [conventions/AGENTS.md](conventions/AGENTS.md) | — |

## Module File Tree

```
modules/
├── domain.nix, hosts.nix, keys.nix, repos.nix, secrets.nix, services.nix
├── iso-installer.nix, installer.nix, binary-cache-client.nix
├── notes/
├── os/
│   ├── default.nix, storage.nix, users.nix, ssh.nix
│   ├── secure-boot.nix, tpm.nix, remote-unlock.nix
│   ├── hardware-key.nix, hypervisor.nix, containers.nix
│   ├── eternal-terminal.nix, airplay.nix, tailscale.nix
│   ├── ollama.nix, immich.nix, iphone-tether.nix
│   ├── notifications.nix, journal-remote.nix
│   ├── git-server/, agents/, scripts/
│   └── agents/ → see modules/os/agents/AGENTS.md
├── terminal/
│   ├── default.nix, shell.nix, editor.nix, ai.nix
│   ├── mail.nix, agent-mail.nix, age-yubikey.nix
│   ├── ssh-auto-load.nix, sandbox.nix, secrets.nix
│   ├── conventions.nix, deepwork.nix, devtools.nix
│   ├── calendar.nix, contacts.nix, timer.nix, tasks.nix
│   ├── forgejo.nix, projects.nix, cli-coding-agent-configs.nix
│   ├── claude-code-commands.nix, claude-code-commands/, claude-code/
│   └── layouts/
├── desktop/
│   ├── nixos.nix
│   └── home/ (components/, hyprland/, scripts/, theming/)
└── server/
    ├── default.nix, lib.nix, acme.nix, nginx.nix, dns.nix
    ├── headscale/, services/
    └── services/ (attic, grafana, prometheus, loki, immich,
                   vaultwarden, forgejo, headscale, miniflux,
                   mail, adguard, seaweedfs)
```

## Flake Exports

### NixOS Modules (`keystone.nixosModules.*`)

| Module | Description |
|--------|-------------|
| `operating-system` | Core OS — storage, Secure Boot, TPM, users, agents (includes disko + lanzaboote) |
| `server` | Server services (includes domain) |
| `desktop` | Hyprland desktop environment |
| `binaryCacheClient` | Attic binary cache client |
| `hardwareKey` | YubiKey/FIDO2 support |
| `isoInstaller` | Bootable installer |
| `domain`, `hosts`, `repos`, `services`, `keys` | Shared options modules |
| `headscale-dns` | Consume server DNS records on headscale host |

### Home-Manager Modules (`keystone.homeModules.*`)

`terminal`, `desktop`, `desktopHyprland`, `notes`

## Packages

### Native (`packages/`)

`zesh`, `agent-mail`, `agent-coding-agent`, `fetch-email-source`, `fetch-forgejo-sources`,
`fetch-github-sources`, `repo-sync`, `podman-agent`, `keystone-tui`, `keystone-installer-ui`,
`keystone-ha`, `ks`, `pz`, `forgejo-project`, `chrome-devtools-mcp`

### Overlay (`pkgs.keystone.*`)

`claude-code`, `gemini-cli`, `codex`, `opencode`, `deepwork`, `keystone-deepwork-jobs`,
`keystone-conventions`, `chrome-devtools-mcp`, `grafana-mcp`, `google-chrome`, `ghostty`,
`yazi`, `himalaya`, `calendula`, `cardamum`, `comodoro`, `cfait`, `agenix`

## Important Notes

- ZFS pool is **always** named `rpool`
- The `operating-system` module includes disko and lanzaboote — no separate import needed
- Terminal and desktop modules are home-manager based, not NixOS system modules
- TPM2 integration requires compatible hardware and UEFI firmware setup
- Secure Boot requires manual key enrollment during installation
- All ZFS datasets use native encryption with automatic key management
- `keystone.repos` auto-populates from flake inputs; `keystone.development` enables local checkout paths

## Keystone Config Repo

The **keystone config repo** is `nixos-config` — the consumer flake that imports keystone
modules and declares per-host/per-user configuration. All keystone-managed repos live
under `~/.keystone/repos/OWNER/REPO/`.

```bash
ks build              # Build home-manager profiles only (fast, no sudo)
ks build --lock       # Full system build + lock + push
ks update --dev       # Deploy home-manager profiles only
ks update             # Full system: pull, lock, build, push, deploy
ks update --lock      # Pull, lock, build, push, deploy (human-only)
```
