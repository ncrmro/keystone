# Keystone

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
| `packages/keystone-tui/` | [packages/keystone-tui/AGENTS.md](packages/keystone-tui/AGENTS.md) | —                                      |
| `conventions/`           | [conventions/AGENTS.md](conventions/AGENTS.md)                     | —                                      |

## Module File Tree

```
modules/
├── domain.nix, hosts.nix, keys.nix, shared/repos.nix, secrets.nix, services.nix
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
| `domain`, `hosts`, `repos`, `services`, `keys` | Shared options modules                                                           |
| `headscale-dns`                                | Consume server DNS records on headscale host                                     |

### Home-Manager Modules (`keystone.homeModules.*`)

`terminal`, `desktop`, `desktopHyprland`, `notes`

## Packages

### Native (`packages/`)

`zesh`, `agent-mail`, `agent-coding-agent`, `fetch-email-source`, `fetch-forgejo-sources`,
`fetch-github-sources`, `repo-sync`, `podman-agent`, `keystone-tui`, `keystone-installer-ui`,
`keystone-ha`, `ks`, `pz`, `forgejo-project`, `chrome-devtools-mcp`, `slidev`

### Overlay (`pkgs.keystone.*`)

`claude-code`, `gemini-cli`, `codex`, `opencode`, `deepwork`, `keystone-deepwork-jobs`,
`keystone-conventions`, `chrome-devtools-mcp`, `grafana-mcp`, `google-chrome`, `ghostty`,
`yazi`, `himalaya`, `calendula`, `cardamum`, `comodoro`, `cfait`, `agenix`, `slidev`

#### llm-agents input strategy

AI agent packages (`claude-code`, `gemini-cli`, `codex`, `opencode`) come from the
`llm-agents` flake input. Keystone keeps this pin at nightly-latest. Consumer flakes
choose one of two strategies:

- **Contributor / nightly-latest**: `llm-agents.follows = "keystone/llm-agents"` —
  relocking keystone automatically bumps agent versions.
- **Stable consumer**: declare an independent `llm-agents` input and override with
  `keystone.inputs.llm-agents.follows = "llm-agents"` — bump manually via
  `nix flake update llm-agents`.

See `modules/terminal/AGENTS.md` § "llm-agents input strategy" for full examples.

## Important Notes

- ZFS pool is **always** named `rpool`
- The `operating-system` module includes disko and lanzaboote — no separate import needed
- Terminal and desktop modules are home-manager based, not NixOS system modules
- TPM2 integration requires compatible hardware and UEFI firmware setup
- Secure Boot requires manual key enrollment during installation
- All ZFS datasets use native encryption with automatic key management
- `keystone.repos` auto-populates from flake inputs; `keystone.development` enables local checkout paths
- **AI Instruction Regeneration**: AI instruction files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) are automatically regenerated from `archetypes.yaml` and the `conventions/` directory during `ks build`, `ks switch`, and `ks update --dev`. In development mode (`keystone.development = true`), these files are symlinked from the repository, and `ks switch` regenerates them as committable git diffs to reflect changes.
- **DeepWork Standard Job Sync**: In `~/.keystone/repos/ncrmro/keystone`, shared DeepWork jobs are discovered through `DEEPWORK_ADDITIONAL_JOBS_FOLDERS`. In development mode, Keystone sets that env var to two job roots:
  `~/.keystone/repos/Unsupervisedcom/deepwork/library/jobs` for shared DeepWork library jobs, and
  `~/.keystone/repos/ncrmro/keystone/.deepwork/jobs` for Keystone-native shared jobs.
  Outside development mode, those same two roots resolve to the packaged derivations `pkgs.keystone.deepwork-library-jobs` and `pkgs.keystone.keystone-deepwork-jobs`.
  When fixing a shared library job discovered through this env var, update the editable files in `~/.keystone/repos/Unsupervisedcom/deepwork/`. When fixing a Keystone-native shared job, update `~/.keystone/repos/ncrmro/keystone/.deepwork/jobs/`. Usually there are no additional per-project DeepWork job files to change beyond the job root already named by `DEEPWORK_ADDITIONAL_JOBS_FOLDERS`.
- DeepWork `keystone_system/issue` draft bodies are temporary artifacts. Write them under `.deepwork/tmp/`, not `.deepwork/jobs/`; the GitHub issue is the canonical source.

## Keystone Config Repo

The **keystone config repo** is `nixos-config` — the consumer flake that imports keystone
modules and declares per-host/per-user configuration. All keystone-managed repos live
under `~/.keystone/repos/OWNER/REPO/`.

For notes workflows, keep the shared owner note repos cloned at:

- `~/.keystone/repos/luce/notes`
- `~/.keystone/repos/drago/notes`

> **CRITICAL: Verifying Changes**
> Agents MUST start with `nix flake check` for repo-native validation and CI parity.
> See `process.testing` for the repository testing policy.
> Tests, CLI regressions, script lint and format checks, and launcher/backend regression checks SHOULD live under `checks` in `flake.nix`, not in ad hoc wrapper scripts.
> `nix flake check` SHOULD cover repo-wide `shellcheck`, repo-wide `nixfmt --check`, deterministic command-contract tests for critical terminal and desktop backends such as `pz`, `ks`, `agentctl`, and Walker or Elephant menu adapters, plus standard example-config integration checks where Keystone has a canonical example config.
> Agents MUST run `ks build` when a change affects host integration, generated assets, or behavior that isolated flake checks cannot validate.
> Agents MUST NOT treat `ks build` as a substitute for adding a deterministic flake check when one can be added.

```bash
nix flake check       # First pass: repo-native checks and CI parity
ks build              # Build home-manager profiles for current host when host integration matters
ks build --lock       # Full system build + lock + push (requires sudo)
ks update --dev       # Deploy home-manager profiles only
ks update             # Full system: pull, lock, build, push, deploy (requires sudo)
ks update --lock      # Pull, lock, build, push, deploy (human-only, requires sudo)
ks switch             # Fast deploy current local state (no pull/lock/push)
ks doctor             # Diagnose system health and validate host status
```
