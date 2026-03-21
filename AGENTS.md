# Keystone

Keystone is a NixOS-based self-sovereign infrastructure platform that enables users to deploy secure, encrypted infrastructure on any hardware. It provides declarative modules for OS configuration, desktop environments, terminal tooling, and server services.

## Module File Tree

```
modules/
├── domain.nix                  Shared keystone.domain option (TLD for services + agents)
├── hosts.nix                   Shared keystone.hosts option (host identity + connection metadata)
├── iso-installer.nix           Bootable NixOS installer with TUI, ZFS, TPM tools
├── binary-cache-client.nix     Attic/Nix binary cache client + watch-store push
├── installer.nix               Installer module (keystoneInputs passthrough)
├── keys.nix                    SSH public key registry (keystone.keys.*)
├── secrets.nix                 Secrets module (rbw/agenix integration)
├── services.nix                Shared service registry (keystone.services.*)
├── notes/
│   └── default.nix             Home-manager notes repo sync (repo-sync on timer)
├── os/
│   ├── default.nix             Orchestrator: keystone.os.* options, imports all submodules
│   ├── agents/                 OS agent provisioning (UIDs 4000+, desktop, mail, git, tasks)
│   │   ├── default.nix        Options declaration + barrel imports
│   │   ├── lib.nix            Shared helpers, constants, filtered agent sets
│   │   ├── types.nix          agentSubmodule type definition
│   │   ├── base.nix           User creation, groups, sudo, home dirs, activation
│   │   ├── agentctl.nix       agentctl CLI + alias wrappers + MCP config
│   │   ├── desktop.nix        labwc + wayvnc services
│   │   ├── chrome.nix         Chromium remote debugging
│   │   ├── dbus.nix           D-Bus socket race fix
│   │   ├── mail-client.nix    himalaya + mail assertions
│   │   ├── tailscale.nix      Per-agent Tailscale (disabled)
│   │   ├── ssh.nix            ssh-agent + assertions
│   │   ├── notes.nix          notes-sync, task-loop, scheduler
│   │   ├── home-manager.nix   Home-manager terminal integration
│   │   ├── observability.nix  Agent observability (Grafana dashboards)
│   │   ├── archetypes/        Agent archetype convention templates (ks-agent.md)
│   │   ├── dashboards/        Agent health dashboards
│   │   └── scripts/           Extracted shell scripts (@placeholder@ pattern)
│   ├── storage.nix             ZFS/ext4 + LUKS credstore, disko partitioning
│   ├── secure-boot.nix         Lanzaboote Secure Boot via sbctl
│   ├── tpm.nix                 TPM-based automatic disk unlock with PCR binding
│   ├── remote-unlock.nix       SSH in initrd for headless remote disk unlock
│   ├── users.nix               User accounts, ZFS homes, home-manager integration
│   ├── ssh.nix                 OpenSSH server with hardened defaults
│   ├── hardware-key.nix        FIDO2/YubiKey SSH + age identity management
│   ├── hypervisor.nix          Libvirt/KVM with OVMF, swtpm, SPICE
│   ├── eternal-terminal.nix    Persistent shell sessions via et
│   ├── airplay.nix             Shairport Sync AirPlay receiver
│   ├── git-server/             Forgejo git server + agent repo provisioning
│   ├── containers.nix          Podman container runtime (fuse-overlayfs for ZFS)
│   ├── notifications.nix       Terminal notification system
│   ├── ollama.nix              Ollama LLM runtime
│   ├── immich.nix              Immich photo management (OS-level)
│   ├── tailscale.nix           Tailscale VPN client
│   ├── iphone-tether.nix       iOS USB tethering via libimobiledevice
│   ├── journal-remote.nix      Centralized journal collection via systemd-journal-remote/upload
│   └── scripts/                Enrollment helpers (TPM, recovery, Secure Boot)
├── terminal/
│   ├── default.nix             Orchestrator: keystone.terminal.* options
│   ├── shell.nix               Zsh, starship, zoxide, direnv, zellij
│   ├── editor.nix              Helix editor with 25+ language servers
│   ├── ai.nix                  Claude Code, Gemini CLI, Codex
│   ├── mail.nix                Himalaya email client configuration
│   ├── agent-mail.nix          Structured email CLI for OS agents
│   ├── age-yubikey.nix         hwrekey workflow, YubiKey identity management
│   ├── ssh-auto-load.nix       Systemd service for auto-loading SSH keys
│   ├── sandbox.nix             Podman-based AI agent sandboxing
│   ├── secrets.nix             rbw (Bitwarden CLI) configuration
│   ├── devtools.nix            csview, jq
│   ├── conventions.nix         Tool-native instruction file generation from keystone conventions
│   ├── deepwork.nix            DeepWork job integration (DEEPWORK_ADDITIONAL_JOBS_FOLDERS)
│   ├── calendar.nix            CalDAV calendar client (calendula)
│   ├── contacts.nix            CardDAV contacts client (cardamum)
│   ├── timer.nix               Pomodoro timer (comodoro)
│   ├── forgejo.nix             Forgejo git integration (forgejo-project CLI)
│   ├── projects.nix            Project management features
│   ├── cli-coding-agent-configs.nix  AI coding agent MCP/config generation
│   └── claude-code/            Claude Code NPM package + update script
├── desktop/
│   ├── nixos.nix               NixOS-level: Hyprland+UWSM, greetd, PipeWire, bluetooth
│   └── home/
│       ├── default.nix         Home-manager desktop orchestrator
│       ├── components/         ghostty, waybar, walker, mako, clipboard, screenshot,
│       │                       ssh-agent, swayosd, btop
│       ├── hyprland/           appearance, autostart, bindings, environment, hypridle,
│       │                       hyprlock, hyprpaper, hyprsunset, input, layout, monitors
│       ├── scripts/            Menu system, screenshot, screenrecord, audio, idle, nightlight
│       └── theming/            15 themes with runtime switching (tokyo-night default)
└── server/
    ├── default.nix             Orchestrator: imports all services + infrastructure
    ├── lib.nix                 mkServiceOptions, accessPresets helpers
    ├── acme.nix                ACME wildcard certs via Cloudflare DNS-01
    ├── nginx.nix               Auto-generated virtualHosts from enabled services
    ├── dns.nix                 DNS record generation for headscale
    ├── headscale/
    │   └── dns-import.nix      Consume generated DNS records on headscale host
    ├── services/
    │   ├── attic.nix           Binary cache (cache.domain, port 8199)
    │   ├── grafana.nix         Observability (grafana.domain, port 3002)
    │   ├── prometheus.nix      Metrics (prometheus.domain, port 9090)
    │   ├── loki.nix            Logs (loki.domain, port 3100)
    │   ├── immich.nix          Photos (photos.domain, port 2283, 50G upload)
    │   ├── vaultwarden.nix     Passwords (vaultwarden.domain, port 8222)
    │   ├── forgejo.nix         Git (git.domain, port 3001)
    │   ├── headscale.nix       VPN control (mercury.domain, port 8080, public)
    │   ├── miniflux.nix        RSS reader (miniflux.domain, port 8070)
    │   ├── mail.nix            Mail admin (mail.domain, port 8082)
    │   ├── adguard.nix         DNS blocking (adguard.home.domain, port 3000)
    │   └── seaweedfs.nix       S3-compatible blob store (s3.domain, port 8333)
    ├── vpn.nix                 Legacy VPN module
    ├── mail.nix                Legacy mail module
    ├── monitoring.nix          Legacy monitoring module
    ├── headscale.nix           Legacy headscale module
    └── observability/          Legacy K8s observability (loki, alloy, kube-prometheus)
```

## OS Module (`modules/os/`)

### Storage

ZFS with LUKS credstore is the primary storage pattern. Pool is always named `rpool`.

```nix
keystone.os.storage = {
  type = "zfs";  # or "ext4"
  devices = [ "/dev/disk/by-id/nvme-..." ];
  mode = "single";  # single, mirror, stripe, raidz1, raidz2, raidz3
  esp.size = "1G";
  swap.size = "8G";
  credstore.size = "100M";  # LUKS volume for ZFS encryption keys
  zfs = { compression = "zstd"; atime = "off"; arcMax = "4G"; autoSnapshot = true; autoScrub = true; };
};
```

**Boot process** (ZFS): Import pool → Unlock credstore (TPM or password) → Load ZFS key → Mount encrypted datasets.

**ext4 alternative**: Simpler LUKS-encrypted ext4 with optional hibernate support. No snapshots/compression.

### Users

```nix
keystone.os.users.alice = {
  fullName = "Alice Smith";
  email = "alice@example.com";
  extraGroups = [ "wheel" "networkmanager" ];
  authorizedKeys = [ "ssh-ed25519 AAAAC3..." ];
  hardwareKeys = [ "yubi-black" ];         # References keystone.hardwareKey.keys
  hashedPassword = "$6$...";               # mkpasswd -m sha-512
  terminal.enable = true;                  # Full keystone.terminal environment
  sshAutoLoad.enable = false;              # Systemd SSH key loading at login
  desktop = {
    enable = false;
    hyprland.modifierKey = "SUPER";
    hyprland.capslockAsControl = true;
  };
  zfs = { quota = "100G"; compression = "lz4"; };
};
```

Users with `terminal.enable` get the full keystone terminal environment via home-manager. Users with `desktop.enable` additionally get the Hyprland desktop. ZFS homes support per-user quotas and compression.

### Agent Provisioning

OS agents are user accounts provisioned via `keystone.os.agents.<name>`. Each agent receives its own identity, credentials, desktop, and workspace.

```nix
keystone.os.agents.drago = {
  uid = null;                    # Auto-assign from 4000+ range
  host = "ncrmro-workstation";   # Where resources are created (feature filtering)
  archetype = "engineer";        # Convention archetype (engineer, product)
  fullName = "Drago";
  email = "agent-drago@example.com";

  terminal.enable = true;        # Full keystone.terminal environment

  desktop = {
    enable = true;
    resolution = "1920x1080";
    vncPort = null;              # Auto-assign from 5901
    vncBind = "0.0.0.0";
  };

  chrome = {
    enable = true;
    debugPort = null;            # Auto-assign from 9222
    mcp.port = null;             # Chrome DevTools MCP, auto-assign from 3101
  };

  grafana = {
    mcp = {
      enable = false;            # Enable Grafana MCP for metrics/logs access
      url = "https://grafana.example.com";
    };
  };

  mail = {
    provision = false;           # Auto-provision on Stalwart host
    address = "agent-drago@example.com";
    imap.port = 993;             # IMAP port override
    smtp.port = 465;             # SMTP port override
  };

  github.username = "drago";     # GitHub username for task loop issue fetching
  forgejo.username = "drago";    # Forgejo username for task loop issue fetching

  git = {
    provision = false;           # Auto-provision on Forgejo host
    username = "drago";
    repoName = "agent-space";    # Auto-created notes repo
  };

  passwordManager.provision = false;  # Emit Vaultwarden provisioning instructions

  mcp.servers = {};              # Additional MCP servers per agent

  # SSH keys are managed via keystone.keys."agent-{name}"

  notes = {
    syncOnCalendar = "*:0/5";    # Every 5 minutes
    taskLoop.onCalendar = "*:0/5";
    taskLoop.maxTasks = 5;
    scheduler.onCalendar = "*-*-* 05:00:00";
  };
};
```

**Headless desktop**: Agents get labwc (Wayland compositor) + wayvnc for remote desktop access.

**Required agenix secrets** (per agent):
- `agent-{name}-ssh-key` — SSH private key
- `agent-{name}-ssh-passphrase` — SSH key passphrase
- `agent-{name}-mail-password` — Stalwart mail password (if mail.provision)

**CRITICAL**: Mail password secrets must list BOTH the agent's `host` (for himalaya client) AND the mail server's host (for Stalwart provisioning).

#### Forgejo CLI vs API

When running on the same server as Forgejo, the `forgejo admin` CLI does **not** require API tokens. It bypasses the HTTP API entirely and talks directly to the database using credentials from `app.ini`. Security is enforced via local file permissions (the command must run as the Forgejo system user).

The CLI only supports a limited set of subcommands: `user create`, `user list`, `user change-password`, `user delete`, `user generate-access-token`, `user must-change-password`, and `user reset-mfa`. There are **no CLI commands** for SSH key management, repository operations, or token deletion.

The provisioning script in `git-server.nix` uses the CLI for user creation and token generation, then uses the HTTP API (via `curl` with the generated token) for SSH key registration and repo creation. The token is deleted via API after provisioning completes.

```bash
# CLI operations (no token needed, must run as forgejo user):
sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user list
sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user create --username <name> ...
sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user generate-access-token --username <name> --token-name <name> --scopes "..." --raw

# API operations (require token, used for SSH keys + repos):
curl -H "Authorization: token $TOKEN" http://127.0.0.1:3000/api/v1/admin/users/<name>/keys
curl -H "Authorization: token $TOKEN" http://127.0.0.1:3000/api/v1/admin/users/<name>/repos
curl -X DELETE -H "Authorization: token $TOKEN" http://127.0.0.1:3000/api/v1/users/<name>/tokens/<token-name>
```

#### Forgejo Project Boards

Forgejo has **no REST API for project boards** (as of 14.x; upstream PR open since Nov 2023). All board operations are automated via the web UI's internal HTTP endpoints using session cookie auth. API tokens and OAuth2 tokens do **not** work for web routes — only session cookies.

The `forgejo-project` CLI wraps these web routes into a `gh project`-like interface. It is available when `keystone.terminal.git.forgejo.enable = true`.

```bash
# Auth — login once, session cookie cached at ~/.local/state/forgejo-project/cookies.txt
# FORGEJO_HOST and FORGEJO_USER can also be set as environment variables
forgejo-project login --host git.example.com --user alice \
  --password-cmd "rbw get git.example.com --field password"

# Project CRUD
forgejo-project create --repo owner/repo --title "v1.0" --template basic-kanban
forgejo-project list   --repo owner/repo                 # outputs JSON
forgejo-project close  --repo owner/repo --project 5
forgejo-project open   --repo owner/repo --project 5
forgejo-project delete --repo owner/repo --project 5

# Column CRUD
forgejo-project column add     --repo owner/repo --project 5 --title "In Review" --color "#0075ca"
forgejo-project column list    --repo owner/repo --project 5  # outputs JSON
forgejo-project column edit    --repo owner/repo --project 5 --column 3 --title "Reviewing"
forgejo-project column default --repo owner/repo --project 5 --column 1
forgejo-project column delete  --repo owner/repo --project 5 --column 3

# Issue management
forgejo-project item add  --repo owner/repo --project 5 --issue 42
forgejo-project item move --repo owner/repo --project 5 --issue 42 --column 3
forgejo-project item list --repo owner/repo --project 5   # outputs JSON
```

Issue numbers are automatically resolved to internal DB IDs via the REST API (`/api/v1/repos/{owner}/{repo}/issues/{number}`), which does accept session cookies.

#### agentctl CLI

`agentctl` is the unified CLI for managing agent services. It dispatches to per-agent helpers via sudo.

```bash
agentctl <agent-name> <command> [args...]
```

| Command | Description |
|---------|-------------|
| `status`, `start`, `stop`, `restart` | `systemctl --user` as the agent |
| `journalctl` | `journalctl --user` as the agent |
| `exec` | Run arbitrary command as the agent (diagnostics) |
| `tasks` | Show agent tasks table (pending/in_progress first) |
| `email` | Show the agent's inbox (recent envelopes) |
| `claude` | Start interactive Claude session in agent notes dir |
| `gemini` | Start interactive Gemini session in agent notes dir |
| `codex` | Start interactive Codex session in agent notes dir |
| `opencode` | Start interactive OpenCode session in agent notes dir |
| `mail` | Send structured email via `agent-mail` |
| `vnc` | Open remote-viewer to the agent's VNC desktop |
| `provision` | Generate SSH keypair, mail password, and agenix secrets |

```bash
agentctl drago status agent-drago-task-loop
agentctl drago journalctl -u agent-drago-task-loop -n 20
agentctl drago exec which himalaya
agentctl drago mail task --subject "Fix CI pipeline"
agentctl drago provision                  # full flow incl. hwrekey
agentctl drago provision --skip-rekey     # skip hwrekey at end
```

**SECURITY**: Per-agent helper scripts hardcode `XDG_RUNTIME_DIR` and allowlist safe systemctl verbs to prevent LD_PRELOAD injection.

### Hypervisor

```nix
keystone.os.hypervisor = {
  enable = true;
  defaultUri = "qemu:///session";
  connections = [ "qemu+ssh://user@server/session" ];
  allowedBridges = [ "virbr0" ];
};
```

- OVMF firmware with Secure Boot support (symlinked to `/run/libvirt/nix-ovmf/`)
- TPM 2.0 emulation via swtpm
- SPICE graphical display
- Polkit rules for `libvirtd` group VM management
- All `keystone.os.users` auto-added to `libvirtd` group
- Home-manager integration: virt-manager bookmarks via dconf

### Hardware Keys

```nix
keystone.hardwareKey = {
  enable = true;
  keys = {
    yubi-black = {
      description = "Primary YubiKey 5 NFC (USB-A, black)";
      sshPublicKey = "sk-ssh-ed25519@openssh.com AAAAC3...";
      ageIdentity = "AGE-PLUGIN-YUBIKEY-...";  # Optional, for agenix
    };
  };
  rootKeys = [ "yubi-black" ];  # Add to root's authorized_keys
  gpgAgent = { enable = true; enableSSHSupport = true; };
};
```

**Services**: pcscd (smart card daemon), GPG agent with SSH support.

**Tools**: `ykman`, `age-plugin-yubikey`, `pam_u2f`, `yubico-piv-tool`.

### Other OS Services

| Service | Option | Description |
|---------|--------|-------------|
| SSH | `keystone.os.ssh.enable` | Hardened OpenSSH (no password auth, no root password login) |
| Eternal Terminal | `keystone.os.services.eternalTerminal` | Persistent sessions surviving network changes (port 2022, tailscale-only) |
| AirPlay | `keystone.os.services.airplay` | Shairport Sync receiver |
| systemd-resolved | `keystone.os.services.resolved` | DNS resolution for Tailscale MagicDNS |
| Containers | `keystone.os.containers.enable` | Podman runtime with fuse-overlayfs for ZFS, docker-compose, DNS networking |
| Tailscale | `keystone.os.tailscale` | Tailscale VPN client |
| iPhone Tether | `keystone.os.iphoneTether.enable` | iOS USB tethering via libimobiledevice and usbmuxd |
| Ollama | `keystone.os.ollama` | Ollama LLM runtime |
| Mail | `keystone.mail.host` | Stalwart mail server (auto-enables on matching host) |
| Git Server | `keystone.os.gitServer` | Forgejo with agent repo provisioning |
| Journal Remote | `keystone.os.journalRemote` | Centralized journal collection via systemd-journal-remote/upload (port 19532, Tailscale-only) |

## Terminal Module (`modules/terminal/`)

The terminal module provides the complete development environment for both human users and OS agents. Agents receive the identical environment — no cherry-picking individual pieces.

**Options**: `keystone.terminal.enable`, `keystone.terminal.editor` (default: "hx"), `keystone.terminal.devTools`, `keystone.terminal.git.*`

### Shell

Zsh with oh-my-zsh (robbyrussell theme), starship prompt, zoxide, direnv+nix-direnv, zellij.

**Shell aliases:**

| Alias | Command | Description |
|-------|---------|-------------|
| `l` / `ls` | `eza -1l` | Modern ls with colors |
| `grep` | `rg` | Ripgrep |
| `g` | `git` | Git shorthand |
| `lg` | `lazygit` | Git TUI |
| `ztab` | `zellij action rename-tab` | Rename zellij tab |
| `zs` | `zesh connect` | Zellij session manager with zoxide |
| `y` | `yazi` | Terminal file manager |

**Zellij keybinds:**

| Keybind | Action |
|---------|--------|
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+T` | New tab |
| `Ctrl+W` | Close tab |
| `Ctrl+Shift+G` | Lock mode (Ctrl+G unbound to avoid Claude Code conflict) |
| `Ctrl+Shift+O` | Session mode (Ctrl+O unbound to avoid lazygit conflict) |
| `Ctrl+PageUp/Down` | Previous/next tab (alternative) |

**Shell packages**: direnv, eza, glow, gnumake, htop, lazygit, ripgrep, tree, yazi, zesh, ghostty.terminfo.

### Editor

Helix editor with custom keybindings and 25+ language servers.

**Custom keybinds:**

| Key | Action |
|-----|--------|
| `Return` | `:write` (save) |
| `F6` | Markdown preview (pipe through helix-preview-markdown) |
| `F7` | Toggle soft wrap |

**Settings**: Line numbers (absolute), mouse enabled, Wayland clipboard, text width 120, soft wrap enabled.

**Language servers:**

| LSP | Languages |
|-----|-----------|
| typescript-language-server | TypeScript, JavaScript |
| bash-language-server | Bash |
| yaml-language-server | YAML |
| dockerfile-language-server | Dockerfile |
| docker-compose-language-service | Docker Compose |
| vscode-json-language-server | JSON, JSON5 |
| vscode-css-language-server | CSS |
| vscode-html-language-server | HTML |
| helm-ls | Helm charts |
| ruby-lsp, solargraph | Ruby |
| marksman | Markdown |
| harper-ls | Grammar/prose (applied to 20+ languages including Nix, Bash, TypeScript, Python, Rust, Go, etc.) |
| nixfmt | Nix (formatter) |
| prettier | TypeScript, Markdown (formatter) |

### Git

```nix
keystone.terminal.git = {
  enable = true;       # Default: true
  userName = "...";    # Required
  userEmail = "...";   # Required
};
```

- **SSH signing**: `gpg.format = "ssh"`, `commit.gpgsign = true`, signing key `~/.ssh/id_ed25519`
- **LFS**: Enabled by default
- **Push**: `push.autoSetupRemote = true`
- **Defaults**: `init.defaultBranch = "main"`, `submodule.recurse = true`
- **Aliases**: `s`=switch, `f`=fetch, `p`=pull, `b`=branch, `st`=status, `co`=checkout, `c`=commit

### AI Tools

Three AI coding assistants available via `keystone.terminal.enable`:

| Tool | Source | Description |
|------|--------|-------------|
| Claude Code | `@anthropic-ai/claude-code` NPM package | Anthropic's CLI agent |
| Gemini CLI | `pkgs.keystone.gemini-cli` (llm-agents flake) | Google's AI assistant |
| Codex | `pkgs.keystone.codex` (llm-agents flake) | OpenAI's coding agent |
| OpenCode | `pkgs.keystone.opencode` (llm-agents flake) | Open-source AI coding agent |

### Mail (Himalaya)

```nix
keystone.terminal.mail = {
  enable = true;
  accountName = "main";
  email = "user@example.com";
  displayName = "User Name";
  login = "username";           # Stalwart account name, NOT email address
  passwordCommand = "cat /run/agenix/mail-password";
  host = "mail.example.com";
};
```

**CRITICAL**: The `login` field is the Stalwart account name (e.g., "ncrmro"), NOT the email address. Using the email as login causes authentication failures.

**Folder mappings** (Stalwart defaults):

| Himalaya | Stalwart |
|----------|----------|
| Sent | Sent Items |
| Drafts | Drafts |
| Trash | Deleted Items |

### Age-YubiKey (`hwrekey`)

Manages YubiKey-based age identities for agenix secrets encryption.

```nix
keystone.terminal.ageYubikey = {
  enable = true;
  identities = [
    { serial = "12345678"; identity = "AGE-PLUGIN-YUBIKEY-..."; }
  ];
  secretsFlakeInput = "agenix-secrets";  # Enables submodule workflow
  configRepoPath = "~/nixos-config";
};
```

**`hwrekey` workflow**: Detects connected YubiKey → matches serial → runs `agenix --rekey` → commits+pushes secrets submodule → updates parent flake input → commits submodule + flake.lock together. Retries up to 3x with 3s backoff for pcscd contention.

```bash
hwrekey -m "chore: add ocean host key"
```

### SSH Auto-Load

Systemd user service that automatically loads SSH keys at login using agenix-managed passphrases.

```nix
keystone.terminal.sshAutoLoad = {
  enable = true;
  # Requires agenix secret: {hostname}-ssh-passphrase
};
```

**SECURITY**: SSH private keys are host-bound (never stored in agenix). Only passphrases are managed as secrets. The service polls for `SSH_AUTH_SOCK` with 5s timeout, then runs `ssh-add` with the passphrase.

### Sandbox (Podman)

Podman-based sandboxing for AI coding agents with persistent Nix store.

```nix
keystone.terminal.sandbox = {
  enable = true;
  memory = "4g";
  cpus = 4;
  volumeName = "nix-agent-store";
  extraCaches = { substituters = [ "..." ]; trustedPublicKeys = [ "..." ]; };
};
```

Sets environment variables (`PODMAN_AGENT_*`) consumed by `podman-agent` package. Pre-resolves Nix store paths for Claude Code, Gemini CLI, Codex, gh, ripgrep, procps.

### Agent Mail

Structured email CLI (`agent-mail`) for sending templated emails to OS agents. Enabled automatically when `keystone.terminal.mail` is enabled.

Templates: task, status, spike, research (implementation in `pkgs.keystone.agent-mail`).

### Secrets (rbw)

```nix
keystone.terminal.secrets = {
  enable = true;
  email = "user@example.com";
  baseUrl = "https://vaultwarden.example.com";  # Optional, for self-hosted
};
```

Bitwarden CLI (`rbw`) for password management. Uses `pinentry-gnome3` by default.

### Conventions

```nix
keystone.terminal.conventions = {
  enable = true;            # Default: true
};
```

Writes keystone conventions to each CLI coding tool's native instruction file (`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md`) at build time. The archetype (set per-agent via `keystone.os.agents.<name>.archetype`) controls which convention set is applied. See `conventions/tool.cli-coding-agents.md`.

### DeepWork

```nix
keystone.terminal.deepwork = {
  enable = true;            # Default: true
};
```

Sets the `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` environment variable for DeepWork job integration, enabling workflow-driven development with quality gates.

### Dev Tools

Enabled via `keystone.terminal.devTools = true`: `csview` (CSV viewer), `jq` (JSON processor).

## Desktop Module (`modules/desktop/`)

### NixOS Level (`nixos.nix`)

```nix
keystone.desktop = {
  enable = true;
  user = "alice";          # User for greetd auto-login
  hyprland.enable = true;  # Default
  greetd.enable = true;
  audio.enable = true;     # PipeWire (ALSA + Pulse + Jack)
  bluetooth.enable = true; # Blueman
  networking.enable = true; # NetworkManager + systemd-resolved
};
```

**Included**: Hyprland + UWSM, greetd auto-login, PipeWire audio, Bluetooth, CUPS printing, NetworkManager, flatpak support, Nerd Fonts (JetBrains Mono, Caskaydia Mono), polkit, OOM protection (Docker/Podman killed first via `OOMScoreAdjust = 1000`).

### Home-Manager Level

Desktop components enabled via `keystone.desktop.enable = true` in home-manager:

| Component | Description |
|-----------|-------------|
| Ghostty | Terminal emulator (JetBrains Mono Nerd Font, 12pt, 0.95 opacity) |
| Waybar | Status bar (workspaces, clock, CPU, battery, bluetooth, network, audio) |
| Walker | App launcher (apps, files, emoji, calculator, web search, clipboard) |
| Mako | Notification daemon (themed) |
| Clipboard | clipse history (100 items) + wl-clipboard + wl-clip-persist |
| Screenshot | grim + slurp + satty annotation |
| SSH Agent | Systemd user service, auto-add keys for 1h |
| SwayOSD | Volume/brightness on-screen display |
| Btop | System monitor (themed) |
| Screen Recording | gpu-screen-recorder with waybar indicator |

### Key Hyprland Bindings

`$mod` is the configured `modifierKey` (default: SUPER). With `altwin:swap_alt_win` always enabled, physical Alt triggers SUPER bindings for ergonomic thumb access.

| Binding | Action |
|---------|--------|
| `$mod+Return` | Terminal (ghostty) |
| `$mod+Space` | App launcher (walker) |
| `$mod+B` | Browser |
| `$mod+E` | File manager |
| `$mod+W` | Close window |
| `$mod+F` | Toggle fullscreen |
| `$mod+Shift+V` | Toggle floating |
| `$mod+H/L` | Focus left/right |
| `$mod+1-0` | Workspace 1-10 |
| `$mod+Shift+1-0` | Move to workspace 1-10 |
| `$mod+Tab` | Next workspace |
| `$mod+S` | Scratchpad toggle |
| `$mod+C/V/X` | Copy/Paste/Cut |
| `$mod+Ctrl+V` | Clipboard manager |
| `$mod+Escape` | Main menu |
| `$mod+K` | Keybinding reference |
| `Print` | Screenshot with editing |

### Key Options

```nix
keystone.desktop.hyprland = {
  modifierKey = "SUPER";       # Primary modifier key
  capslockAsControl = true;    # Remap Caps Lock → Control
  scale = 2;                   # HiDPI scale factor (1 or 2)
  terminal = "uwsm app -- ghostty";
  browser = "uwsm app -- chromium --new-window --ozone-platform=wayland";
  touchpad.dragLock = false;
};
keystone.desktop.monitors = {
  primaryDisplay = "eDP-1";
  autoMirror = true;           # Auto-mirror to new displays
};
keystone.desktop.theme.name = "tokyo-night";  # 15 themes available
```

**Keyboard note**: `altwin:swap_alt_win` is always enabled. This swaps Alt and Super so that the physical Alt key (thumb-accessible) triggers `$mod` bindings. Set `modifierKey = "SUPER"` to use physical Alt as modifier.

### Theming

15 themes with runtime switching via `keystone-theme-switch <name>`:

tokyo-night (default), kanagawa, catppuccin, catppuccin-latte, ethereal, everforest, flexoki-light, gruvbox, hackerman, matte-black, nord, osaka-jade, ristretto, rose-pine, royal-green.

Each theme provides: Hyprland colors, hyprlock, waybar CSS, mako, wofi, btop, swayosd, walker CSS, ghostty, helix, zellij theme mappings, and wallpapers.

## Server Module (`modules/server/`)

### Service Pattern

Each service uses `mkServiceOptions` from `lib.nix`:

```nix
keystone.server.services.<name> = mkServiceOptions {
  description = "Service description";
  subdomain = "<name>";
  port = 8080;
  access = "tailscale";
  websockets = true;
};
```

When enabled, the service registers in `_enabledServices`, and nginx/dns modules auto-generate virtualHosts and DNS records.

### Access Presets

| Preset | Networks |
|--------|----------|
| `tailscale` | 100.64.0.0/10, fd7a:115c:a1e0::/48 |
| `tailscaleAndLocal` | Tailscale + 192.168.1.0/24 |
| `public` | No restrictions |
| `local` | 192.168.1.0/24 only |

### Available Services

| Service | Subdomain | Port | Access | Notes |
|---------|-----------|------|--------|-------|
| attic | cache | 8199 | tailscale | Binary cache, auto-init, gc (12h) |
| immich | photos | 2283 | tailscale | maxBodySize=50G |
| vaultwarden | vaultwarden | 8222 | tailscale | |
| forgejo | git | 3001 | tailscale | |
| grafana | grafana | 3002 | tailscale | Default disk alert rules |
| prometheus | prometheus | 9090 | tailscale | |
| loki | loki | 3100 | tailscale | |
| headscale | mercury | 8080 | **public** | |
| miniflux | miniflux | 8070 | tailscale | |
| mail | mail | 8082 | tailscale | Stalwart admin |
| adguard | adguard.home | 3000 | tailscaleAndLocal | |
| seaweedfs | s3 | 8333 | tailscale | S3-compatible blob store |

### DNS Pipeline

1. Each enabled service registers in `keystone.server._enabledServices`
2. `dns.nix` generates records to `keystone.server.generatedDNSRecords`
3. Headscale host imports via `keystone.headscale.dnsRecords`
4. Headscale distributes to all tailnet clients via MagicDNS

### Adding New Services

1. Create `modules/server/services/<name>.nix` using `mkServiceOptions`
2. Register in `_enabledServices` when enabled
3. Import in `modules/server/default.nix`

### Port Conflict Detection

Automatic assertion fails with a clear error if two enabled services share a port.

### Warning Pattern

Server modules emit `warnings` (not `assertions`) for missing recommended config (e.g., `keystone.domain == null`). Evaluation always succeeds.

### Legacy Modules

`binaryCache`, `monitoring`, `vpn`, `mail`, `headscale` — configure only the service itself. Consumer handles nginx/TLS/access. Migration to `services.*` pattern pending.

## Domain Architecture

```nix
keystone.domain = "example.com";
keystone.server.services.immich.enable = true;   # → photos.example.com
keystone.os.agents.drago = {};                    # → agent-drago@example.com
```

The `keystone.domain` option (defined in `modules/domain.nix`) establishes a shared TLD used by both server services and OS agents. Each service has a `subdomain` option that defaults to the service name but can be overridden.

## Packages

### Keystone Native (`packages/`)

| Package | Description |
|---------|-------------|
| zesh | Zellij session manager with zoxide integration (Rust) |
| agent-mail | Structured email templates for OS agents (shell) |
| agent-coding-agent | Coding task orchestrator: branch, invoke subagent, push, PR, review (shell) |
| fetch-email-source | Fetch email envelopes + bodies via himalaya (shell) |
| fetch-forgejo-sources | Fetch Forgejo issue/PR data for agent context (shell) |
| fetch-github-sources | Fetch GitHub issue/PR data for agent context (shell) |
| repo-sync | Clone-if-absent, fetch/commit/rebase/push sync for git repos (shell) |
| podman-agent | Run AI coding agents in Podman containers with persistent Nix store (shell) |
| keystone-tui | Installer and configuration TUI (Rust) |
| keystone-installer-ui | Installer UI components (React/Ink) |
| keystone-ha | Cross-realm resource management TUI (Rust) |
| ks | NixOS configuration build/update CLI (shell) |
| pz | Project management CLI (shell) |
| forgejo-project | Forgejo project board CLI via web routes (shell) |
| chrome-devtools-mcp | Chrome DevTools Protocol MCP server (shell) |

### Overlay (`pkgs.keystone.*`)

| Package | Source |
|---------|--------|
| claude-code | llm-agents flake |
| gemini-cli | llm-agents flake |
| codex | llm-agents flake |
| opencode | llm-agents flake |
| deepwork | deepwork flake |
| keystone-deepwork-jobs | local derivation (.deepwork/jobs/) |
| keystone-conventions | local derivation (conventions/) |
| chrome-devtools-mcp | packages/chrome-devtools-mcp |
| grafana-mcp | grafana/mcp-grafana (Go) |
| google-chrome | browser-previews flake |
| ghostty | ghostty flake |
| yazi | yazi flake |
| himalaya | himalaya flake |
| calendula | pimalaya/calendula flake |
| cardamum | pimalaya/cardamum flake |
| comodoro | pimalaya/comodoro flake |
| agenix | agenix flake |

## Deployment Patterns

### Pattern 1: Headless Server

```nix
keystone.os.enable = true;
keystone.server.enable = true;
```

### Pattern 2: Workstation with Desktop

```nix
keystone.os.enable = true;
keystone.os.users.alice.desktop.enable = true;
```

### Pattern 3: Multi-Service Server

```nix
keystone.domain = "example.com";
keystone.os.enable = true;
keystone.server = {
  enable = true;
  tailscaleIP = "100.64.0.6";
  acme.enable = true;
  services = { immich.enable = true; vaultwarden.enable = true; };
};
```

## Development and Testing

### Fast VM Testing (`bin/build-vm`)

```bash
./bin/build-vm terminal             # Build + auto-SSH
./bin/build-vm desktop              # Build + graphical console
./bin/build-vm terminal --clean     # Clean + rebuild
./bin/build-vm terminal --build-only
```

Credentials: `testuser/testpass`, `root/root`. Mounts host Nix store via 9P for fast builds.

### MicroVM Testing

Lightweight tests for specific modules (TPM, networking) via `microvm.nix`:

```bash
nix develop --command bin/test-microvm-tpm
```

### Full Stack VM Testing (`bin/virtual-machine`)

Libvirt VMs with UEFI Secure Boot setup mode, TPM 2.0 emulation, SPICE display:

```bash
./bin/virtual-machine --name keystone-test-vm --start
./bin/virtual-machine --post-install-reboot keystone-test-vm
./bin/virtual-machine --reset keystone-test-vm
```

SSH: `./bin/test-vm-ssh` (isolated known_hosts, auto-connects to 192.168.100.99).

### Make Targets

| Category | Targets |
|----------|---------|
| ISO | `make build-iso`, `make build-iso-ssh` |
| Fast VM | `make build-vm-terminal`, `make build-vm-desktop` |
| Libvirt | `make vm-create`, `make vm-ssh`, `make vm-reset`, `make vm-post-install` |
| Tests | `make test`, `make test-checks`, `make test-module`, `make test-integration` |
| CI | `make ci`, `make fmt` |

### VM Screenshot Debugging

```bash
./bin/screenshot keystone-test-vm    # -> screenshots/vm-screenshot-*.png
```

Read the PNG directly for visual inspection of boot failures, Secure Boot issues, or initrd prompts.

## Flake Exports

### NixOS Modules

| Module | Import Path | Description |
|--------|-------------|-------------|
| operating-system | `keystone.nixosModules.operating-system` | Core OS (storage, secure boot, TPM, users, agents; imports domain + disko + lanzaboote) |
| server | `keystone.nixosModules.server` | Server services (imports domain) |
| desktop | `keystone.nixosModules.desktop` | Hyprland desktop environment |
| binaryCacheClient | `keystone.nixosModules.binaryCacheClient` | Attic binary cache client |
| hardwareKey | `keystone.nixosModules.hardwareKey` | YubiKey/FIDO2 support |
| isoInstaller | `keystone.nixosModules.isoInstaller` | Bootable installer |
| domain | `keystone.nixosModules.domain` | Shared keystone.domain option |
| mail | `keystone.nixosModules.mail` | Shared keystone.mail.host option (mail server host) |
| hosts | `keystone.nixosModules.hosts` | Shared keystone.hosts option (host identity + connection metadata) |
| services | `keystone.nixosModules.services` | Shared service registry (keystone.services.*) |
| keys | `keystone.nixosModules.keys` | SSH public key registry (keystone.keys.*) |
| headscale-dns | `keystone.nixosModules.headscale-dns` | Consume server DNS records on headscale host |

### Home-Manager Modules

| Module | Import Path | Description |
|--------|-------------|-------------|
| terminal | `keystone.homeModules.terminal` | Terminal dev environment |
| desktop | `keystone.homeModules.desktop` | Hyprland desktop home config |
| desktopHyprland | `keystone.homeModules.desktopHyprland` | Hyprland compositor module |
| notes | `keystone.homeModules.notes` | Notes repo sync (repo-sync on timer) |

### Key Options

| Option | Description |
|--------|-------------|
| `keystone.domain` | Shared TLD for services + agents |
| `keystone.mail.host` | Hostname of mail server (auto-enables Stalwart) |
| `keystone.hosts` | Host identity + connection metadata (hostname, sshTarget, fallbackIP, buildOnRemote, role, baremetal, hostPublicKey, zfs) |
| `keystone.terminal.enable` | Enable terminal tools (zsh, starship, zellij, helix) |
| `keystone.terminal.git.userName/userEmail` | Required git config |
| `keystone.desktop.enable` | Enable desktop environment |
| `keystone.desktop.hyprland.modifierKey` | Primary modifier (default: SUPER) |
| `keystone.desktop.hyprland.capslockAsControl` | Remap caps → ctrl (default: true) |

## Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

**Format**: `<type>([scope]): <description>`

**Types**: `feat`, `fix`, `chore`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `revert`.

**Scopes**: `agent`, `os`, `desktop`, `terminal`, `server`, `tpm`, `cli`.

Reference specs: `fix(os): [SPEC-003] Correct Secure Boot key enrollment flow`

## Code Comment Conventions

### File-Level Documentation
Every non-trivial file starts with a header block explaining what the module does, its security model, and usage examples. For Nix files, use a `#` comment block at top of file (see `modules/os/agents.nix` as exemplar).

### Inline Comments
- **Why, not what** — code should be self-documenting; comments explain *why* a choice was made
- **SECURITY:** prefix — security-critical design decision; name the specific threat being mitigated
- **CRITICAL:** prefix — cross-module invariant that breaks silently if violated
- **TODO:** prefix — known gap with consequences explained, not just "fix later"

For security decisions, always name the specific attack vector being mitigated.

## Important Notes

- ZFS pool is always named `rpool`
- The `operating-system` module includes disko and lanzaboote — no separate import needed
- Terminal and desktop modules are home-manager based, not NixOS system modules
- TPM2 integration requires compatible hardware and UEFI firmware setup
- Secure Boot requires manual key enrollment during installation
- All ZFS datasets use native encryption with automatic key management
- Home-manager integration is optional and only configured when imported

## Submodule Usage in nixos-config

When keystone is used as a git submodule in another flake:

```nix
keystone = {
  url = "git+file:./.submodules/keystone?submodules=1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Use `ks build` and `ks update` to manage builds and deployments:
```bash
ks build                     # Build home-manager profiles only (fast, no sudo)
ks build --lock              # Full system build + lock + push
ks update --dev              # Deploy home-manager profiles only
ks update                    # Full system: pull, lock, build, push, deploy
ks update --dev --boot       # Not applicable (home-manager only, no boot needed)
```
