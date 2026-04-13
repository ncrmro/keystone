# Keystone

@CONTRIBUTOR.md — development workflow, verification commands, and deployment flow

Keystone is a NixOS-based self-sovereign infrastructure platform for deploying secure,
encrypted infrastructure on any hardware. It provides declarative modules for OS
configuration, desktop environments, terminal tooling, and server services.

## Module Navigation

| Module                   | Editing Guide                                                      | User-facing Docs                       |
| ------------------------ | ------------------------------------------------------------------ | -------------------------------------- |
| `modules/os/`            | [modules/os/AGENTS.md](modules/os/AGENTS.md)                       | [docs/os-agents.md](docs/os-agents.md) |
| `modules/os/agents/`     | [modules/os/agents/AGENTS.md](modules/os/agents/AGENTS.md)         | [docs/agents.md](docs/agents.md)       |
| `modules/terminal/`      | [modules/terminal/AGENTS.md](modules/terminal/AGENTS.md)           | [docs/terminal.md](docs/terminal.md)   |
| `modules/desktop/`       | [modules/desktop/AGENTS.md](modules/desktop/AGENTS.md)             | —                                      |
| `modules/server/`        | [modules/server/AGENTS.md](modules/server/AGENTS.md)               | [docs/server.md](docs/server.md)       |
| `packages/ks/` | [packages/ks/AGENTS.md](packages/ks/AGENTS.md) | —                                      |
| `conventions/`           | [conventions/AGENTS.md](conventions/AGENTS.md)                     | —                                      |
| `docs/testing/`          | —                                                                  | [docs/testing/iso-os-virtual-machine.md](docs/testing/iso-os-virtual-machine.md) |

## Module File Tree

```
modules/
├── domain.nix, hosts.nix, keys.nix, secrets.nix, services.nix
├── shared/experimental.nix, shared/repos.nix, shared/dev-script-link.nix
├── iso-installer.nix, installer.nix, binary-cache-client.nix
├── notes/
├── os/
│   ├── default.nix, storage.nix, users.nix, ssh.nix
│   ├── secure-boot.nix, tpm.nix, remote-unlock.nix
│   ├── hardware-key.nix, hypervisor.nix, containers.nix
│   ├── eternal-terminal.nix, airplay.nix, tailscale.nix
│   ├── ollama.nix, immich.nix, iphone-tether.nix
│   ├── alloy.nix, mail.nix, observability.nix
│   ├── notifications.nix, journal-remote.nix
│   ├── privileged-approval.nix, uhk.nix
│   ├── git-server/, agents/, scripts/
│   └── agents/ → see modules/os/agents/AGENTS.md
├── terminal/
│   ├── default.nix, shell.nix, editor.nix, ai.nix
│   ├── mail.nix, agent-mail.nix, age-yubikey.nix
│   ├── ssh-auto-load.nix, sandbox.nix, secrets.nix
│   ├── conventions.nix, deepwork.nix, devtools.nix
│   ├── calendar.nix, contacts.nix, timer.nix, tasks.nix
│   ├── forgejo.nix, grafana.nix, projects.nix
│   ├── cli-coding-agent-configs.nix, ai-extensions.nix
│   ├── generated-agent-assets.nix, perception.nix
│   ├── claude-code/, ai-commands/, agent-assets/
│   └── layouts/, scripts/
├── desktop/
│   ├── nixos.nix
│   └── home/ (components/, hyprland/, scripts/, theming/)
└── server/
    ├── default.nix, lib.nix, acme.nix, nginx.nix, dns.nix
    ├── headscale.nix, mail.nix, monitoring.nix, vpn.nix
    ├── headscale/, observability/, services/
    └── services/ (attic, grafana, prometheus, loki, immich,
                   vaultwarden, forgejo, headscale, miniflux,
                   mail, adguard, seaweedfs, journal-remote)
```

## Flake Exports

### NixOS Modules (`keystone.nixosModules.*`)

| Module                                         | Description                                                                      |
| ---------------------------------------------- | -------------------------------------------------------------------------------- |
| `operating-system`                             | Core OS — storage, Secure Boot, TPM, users, agents (includes disko + lanzaboote) |
| `server`                                       | Server services (includes domain)                                                |
| `desktop`                                      | Hyprland desktop environment                                                     |
| `binaryCacheClient`                            | Attic binary cache client                                                        |
| `hardwareKey`                                  | YubiKey/FIDO2 support                                                            |
| `isoInstaller`                                 | Bootable installer                                                               |
| `experimental`                                 | Experimental feature flag (`keystone.experimental`)                              |
| `domain`, `hosts`, `repos`, `services`, `keys` | Shared options modules                                                           |
| `headscale-dns`                                | Consume server DNS records on headscale host                                     |

### Home-Manager Modules (`keystone.homeModules.*`)

`terminal`, `desktop`, `desktopHyprland`, `notes`

## Packages

### Native (`packages/`)

`zesh`, `agent-mail`, `agent-coding-agent`, `fetch-email-source`, `fetch-forgejo-sources`,
`fetch-github-sources`, `repo-sync`, `podman-agent`, `ks`, `keystone-ha`,
`pz`, `forgejo-project`, `forgejo-cli-ex`, `chrome-devtools-mcp`, `grafana-mcp`,
`lfs-s3`, `slidev`, `cfait`, `zellij-tab-name`, `hyprpolkitagent`, `agents-e2e`,
`keystone-conventions`, `keystone-deepwork-jobs`, `deepwork-library-jobs`

### Overlay (`pkgs.keystone.*`)

`claude-code`, `gemini-cli`, `codex`, `opencode`, `deepwork`, `keystone-deepwork-jobs`,
`keystone-conventions`, `chrome-devtools-mcp`, `grafana-mcp`, `google-chrome`, `ghostty`,
`yazi`, `himalaya`, `calendula`, `cardamum`, `comodoro`, `cfait`, `agenix`, `slidev`

## Important Notes

- ZFS pool is **always** named `rpool`
- The `operating-system` module includes disko and lanzaboote — no separate import needed
- Terminal and desktop modules are home-manager based, not NixOS system modules
- TPM2 integration requires compatible hardware and UEFI firmware setup
- Secure Boot requires manual key enrollment during installation
- All ZFS datasets use native encryption with automatic key management
- `keystone.repos` auto-populates from flake inputs; `keystone.development` enables local checkout paths
- `keystone.experimental` (default `false`) gates experimental features. When `true`, experimental modules auto-enable. Defined in `modules/shared/experimental.nix` — a zero-dependency module imported everywhere. See `docs/experimental.md` for the full list and module author guide.

## Keystone Config Repo

The **keystone config repo** is `nixos-config` — the consumer flake that imports keystone
modules and declares per-host/per-user configuration. All keystone-managed repos live
under `~/.keystone/repos/OWNER/REPO/`.

For notes workflows, keep the shared owner note repos cloned at:

- `~/.keystone/repos/luce/notes`
- `~/.keystone/repos/drago/notes`

