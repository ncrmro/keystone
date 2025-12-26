---
layout: default
title: Agent Sandbox User Guide
---

# Agent Sandbox User Guide

Run AI coding agents (Claude Code, Gemini CLI, Codex) in isolated, secure MicroVM sandboxes.

## Overview

The Agent Sandbox provides isolated environments where AI agents can operate autonomously without requiring permission prompts for file changes, command execution, or network access. Your host system remains protected while agents work freely.

**Key Benefits:**
- **Isolation**: Agents run in a separate VM with no access to host credentials or files outside the workspace
- **Autonomy**: No permission prompts - agents can modify files, run commands, install packages
- **Persistence**: Sandbox state survives between sessions
- **Security**: Host-initiated sync ensures agents cannot push changes without your review

## Prerequisites

- **NixOS** with flakes enabled
- **KVM support** (`/dev/kvm` must exist)
- A **git repository** for your project
- (Optional) **SSH key** in `~/.ssh/` for passwordless authentication

Check KVM availability:
```bash
ls -la /dev/kvm
# Should show the device exists
```

## Quick Start

```bash
# 1. Navigate to your project
cd ~/projects/my-app

# 2. Start a sandbox (builds on first run, ~2 min)
keystone agent start

# 3. You're now SSH'd into the sandbox at /workspace
# Run your agent, make changes, etc.

# 4. Detach with Ctrl-D or 'exit'

# 5. Sync committed changes back to host
keystone agent sync

# 6. Stop the sandbox when done
keystone agent stop
```

## Core Workflows

### Starting Your First Sandbox

```bash
cd ~/projects/my-web-app
keystone agent start
```

**What happens:**
1. The CLI clones your project into the sandbox workspace
2. A MicroVM is built with NixOS and basic dev tools
3. The VM boots and SSH becomes available
4. You're automatically attached to an SSH session

**First run** takes ~2 minutes to build. Subsequent starts are faster (~30 seconds).

**Inside the sandbox:**
- Your project is at `/workspace/`
- The `sandbox` user has sudo access
- Git, Python, Vim, curl, wget, htop are pre-installed
- Changes you make are visible to the agent

### Getting Changes Back to Host

The sandbox is isolated - it cannot push directly to your host. Instead, use `keystone agent sync` to pull changes:

```bash
# Inside sandbox: make changes and commit
cd /workspace
git add .
git commit -m "Agent's improvements"

# Exit sandbox (Ctrl-D or 'exit')

# On host: sync the changes
keystone agent sync
```

**Sync behavior:**
- Only **committed changes** are synced (uncommitted files are shown but not transferred)
- Uses `git fetch` + `git merge --ff-only` for safety
- If your host has diverged, you'll get manual merge instructions

**Preview before syncing:**
```bash
keystone agent sync --dry-run
```

**Sync build artifacts too:**
```bash
keystone agent sync --artifacts
# Syncs: dist/, build/, target/, .next/, out/
```

### Running Multiple Sandboxes

By default, sandbox names are derived from the project directory. You can run multiple:

```bash
# Terminal 1: Web frontend
cd ~/projects/frontend
keystone agent start --no-attach

# Terminal 2: API backend
cd ~/projects/backend
keystone agent start --no-attach

# See all running sandboxes
keystone agent list

# Attach to a specific one
keystone agent attach backend
```

**Custom names:**
```bash
keystone agent start --name my-custom-sandbox
```

### Reconnecting to a Sandbox

Sandboxes persist between sessions. To reconnect:

```bash
# Check status
keystone agent status my-app

# Reattach
keystone agent attach my-app
# or
keystone agent ssh my-app
```

**Starting fresh:**
```bash
keystone agent start --fresh
# Discards previous state and starts clean
```

### Running Commands Without Attaching

```bash
# Run a single command
keystone agent exec my-app -- npm test

# Check git status in sandbox
keystone agent exec my-app -- git -C /workspace status

# Multiple commands
keystone agent exec -- bash -c "cd /workspace && npm install && npm test"
```

## Command Reference

### keystone agent start

Launch a sandbox for a project.

```bash
keystone agent start [path] [options]
```

**Arguments:**
- `path` - Project directory (default: current directory)

**Options:**
| Option | Description |
|--------|-------------|
| `--name <name>` | Custom sandbox name (default: directory name) |
| `--memory <MB>` | RAM allocation (default: 8192) |
| `--vcpus <N>` | Virtual CPUs (default: 4) |
| `--no-nested` | Disable nested virtualization |
| `--fresh` | Discard previous state |
| `--no-attach` | Don't auto-attach after starting |
| `--network <mode>` | Network mode: user, tap, macvtap, bridge (default: user) |
| `--sync-mode <mode>` | Sync mode: manual, auto-commit, auto-idle (default: manual) |

**Exit codes:**
- `0` - Success
- `1` - Not a git repository
- `2` - Sandbox already running (use `--fresh` or attach)
- `3` - Build failed
- `4` - KVM not available

### keystone agent stop

Stop a running sandbox.

```bash
keystone agent stop [name] [options]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--sync` | Sync changes before stopping |

### keystone agent attach / ssh

SSH into a running sandbox.

```bash
keystone agent attach [name]
keystone agent ssh [name]
```

These commands are equivalent. Detach with `Ctrl-D` or `exit`.

### keystone agent exec

Run a command in the sandbox.

```bash
keystone agent exec [name] -- <command>
```

**Example:**
```bash
keystone agent exec -- ls -la /workspace
keystone agent exec my-app -- npm run build
```

### keystone agent sync

Sync committed changes from sandbox to host.

```bash
keystone agent sync [name] [options]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--dry-run` | Preview what would be synced |
| `--artifacts` | Also sync build directories |

**Exit codes:**
- `0` - Sync completed
- `1` - Sandbox not found or not running
- `2` - No changes to sync
- `3` - Merge conflict (manual resolution needed)

### keystone agent status

Show sandbox status.

```bash
keystone agent status [name] [options]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--json` | Output as JSON |

### keystone agent list

List all sandboxes.

```bash
keystone agent list [options]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--json` | Output as JSON |

### keystone agent destroy

Remove a sandbox completely.

```bash
keystone agent destroy <name> [options]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--force` | Skip confirmation, force destroy if running |

## Configuration

### State Directory

All sandbox state is stored in `~/.config/keystone/agent/`:

```
~/.config/keystone/agent/
├── sandboxes.json           # Registry of all sandboxes
└── sandboxes/
    └── <sandbox-name>/
        ├── workspace/       # Git clone of your project
        └── state/
            ├── flake.nix    # Generated NixOS configuration
            ├── runner/      # MicroVM runner scripts
            └── microvm.pid  # Process ID when running
```

### Default Resources

| Resource | Default | Minimum |
|----------|---------|---------|
| Memory | 8192 MB | 2048 MB |
| vCPUs | 4 | 1 |
| Network | user mode | - |

### SSH Authentication

The agent automatically detects SSH keys in this order:
1. `~/.ssh/id_ed25519.pub`
2. `~/.ssh/id_rsa.pub`
3. `~/.ssh/id_ecdsa.pub`

If no key is found, password authentication is enabled with password `sandbox`.

**Generate an SSH key:**
```bash
ssh-keygen -t ed25519
```

## Troubleshooting

### KVM Not Available

**Error:** `KVM is not available on this system`

**Solutions:**
1. Check if the module is loaded: `lsmod | grep kvm`
2. Load the module: `sudo modprobe kvm_intel` or `sudo modprobe kvm_amd`
3. Verify in BIOS that virtualization (VT-x/AMD-V) is enabled

### Build Failures

**Error:** `Failed to build MicroVM`

**Solutions:**
1. First build requires network access to fetch nixpkgs and microvm.nix
2. Check your network connection
3. Try rebuilding: `keystone agent start --fresh`

### SSH Connection Issues

**Error:** `Permission denied` or `Connection refused`

**Solutions:**
1. Wait longer - VM may still be booting (try `keystone agent status`)
2. Check port 2223 is not in use: `ss -tlnp | grep 2223`
3. Verify SSH key is correctly configured
4. Try password auth: `ssh -p 2223 sandbox@localhost` (password: `sandbox`)

### Sandbox Won't Stop

**Solution:** Use force destroy:
```bash
keystone agent destroy <name> --force
```

Or manually kill the process:
```bash
kill $(cat ~/.config/keystone/agent/sandboxes/<name>/state/microvm.pid)
```

## Security Model

### What's Isolated

- **Filesystem**: Sandbox cannot access host files outside `/workspace/`
- **Credentials**: Host SSH keys, API tokens, etc. are not accessible
- **Network**: User-mode networking (no raw network access)
- **Processes**: Sandbox processes cannot see host processes

### What's Shared

- **Workspace**: Your project directory is mounted at `/workspace/` (via 9p)
- **SSH Port**: Port 2223 is forwarded to the sandbox (localhost only)

### Sync Security

- The sandbox **cannot push** to your host repository
- All transfers are **host-initiated** via `keystone agent sync`
- You review changes before they land on your host branch

## See Also

- **[Architecture Deep Dive](agent-microvms.md)** - How MicroVMs work
- **[CLI Quick Reference](../packages/keystone-agent/README.md)** - Command cheatsheet
- **[Specification](../specs/012-agent-sandbox/spec.md)** - Full feature specification
