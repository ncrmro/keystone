# Keystone Agent CLI

Run AI coding agents (Claude Code, Gemini CLI, Codex) in isolated MicroVM sandboxes.

## Quick Start

```bash
# Navigate to your project
cd ~/projects/my-app

# Start a sandbox
keystone agent start

# Work inside the sandbox (auto-attached via SSH)
# Make changes, run tests, let the agent work...

# Sync changes back to host
keystone agent sync

# When done
keystone agent stop
```

## Commands

| Command | Description |
|---------|-------------|
| `start [path]` | Start sandbox for a project |
| `stop [name]` | Stop a running sandbox |
| `attach [name]` | SSH into sandbox |
| `ssh [name]` | Alias for attach |
| `exec [name] -- <cmd>` | Run command in sandbox |
| `sync [name]` | Sync committed changes back to host |
| `status [name]` | Show sandbox status |
| `list` | List all sandboxes |
| `destroy <name>` | Remove sandbox completely |

## Common Options

### start
| Option | Description |
|--------|-------------|
| `--memory <MB>` | RAM allocation (default: 8192) |
| `--vcpus <N>` | Virtual CPU count (default: 4) |
| `--fresh` | Discard previous state, start clean |
| `--no-attach` | Start without auto-attaching |
| `--name <name>` | Custom sandbox name |
| `--no-nested` | Disable nested virtualization |

### sync
| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be synced |
| `--artifacts` | Also sync build directories (dist/, build/, etc.) |

### status / list
| Option | Description |
|--------|-------------|
| `--json` | Output in JSON format |

## Sandbox Model

- **One sandbox per project** by default (name derived from directory)
- Create multiple sandboxes with explicit `--name` flag
- Sandbox state persists between sessions (use `--fresh` to reset)

## Configuration

State is stored in `~/.config/keystone/agent/`:
```
~/.config/keystone/agent/
├── sandboxes.json       # Sandbox registry
└── sandboxes/           # Per-sandbox state
    └── <name>/
        ├── workspace/   # Cloned git repository
        └── state/       # MicroVM configuration
```

## SSH Access

- SSH key authentication is automatic (uses `~/.ssh/id_ed25519.pub` etc.)
- Falls back to password `sandbox` if no key found
- Direct access: `ssh -p 2223 sandbox@localhost`

## See Also

- **[Full User Guide](../../docs/agent-sandbox.md)** - Detailed workflows and troubleshooting
- **[Architecture](../../docs/agent-microvms.md)** - Technical deep-dive
