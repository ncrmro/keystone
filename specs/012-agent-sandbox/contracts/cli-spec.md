# CLI Specification: Agent Sandbox

**Branch**: `012-agent-sandbox` | **Date**: 2025-12-24

This document defines the command-line interface for the Agent Sandbox system.

## Command Structure

```text
keystone agent <subcommand> [options] [arguments]
```

## Subcommands

### `keystone agent start`

Launch a sandbox for the current project.

**Usage**:
```bash
keystone agent start [OPTIONS] [PROJECT_PATH]
```

**Arguments**:
- `PROJECT_PATH` - Path to git repository (default: current directory)

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--name` | string | derived | Sandbox name (derived from project if omitted) |
| `--memory` | int | 8192 | RAM in MB |
| `--vcpus` | int | 4 | Virtual CPU count |
| `--no-nested` | flag | false | Disable nested virtualization |
| `--fresh` | flag | false | Discard previous sandbox state |
| `--network` | enum | nat | Network mode: nat, none, bridge |
| `--sync-mode` | enum | manual | Sync mode: manual, auto-commit, auto-idle |
| `--no-attach` | flag | false | Start without attaching to session |
| `--agent` | string | none | Auto-start agent: claude, gemini, codex |

**Examples**:
```bash
# Start sandbox for current project
keystone agent start

# Start with custom resources
keystone agent start --memory 16384 --vcpus 8

# Start fresh (discard previous state)
keystone agent start --fresh

# Start and auto-launch Claude Code
keystone agent start --agent claude

# Start in background
keystone agent start --no-attach
```

**Exit Codes**:
- `0` - Sandbox started successfully
- `1` - Project path is not a git repository
- `2` - Sandbox already running for this project
- `3` - Insufficient system resources
- `4` - KVM not available

**Output**:
```text
Starting sandbox 'myproject'...
  Memory: 8192 MB
  vCPUs: 4
  Nested virt: enabled
  Sync mode: manual

Sandbox ready. Attaching to session...
```

---

### `keystone agent stop`

Stop a running sandbox.

**Usage**:
```bash
keystone agent stop [OPTIONS] [SANDBOX_NAME]
```

**Arguments**:
- `SANDBOX_NAME` - Name of sandbox to stop (default: current project's sandbox)

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--force` | flag | false | Force stop without graceful shutdown |
| `--sync` | flag | false | Sync changes before stopping |

**Examples**:
```bash
# Stop current project's sandbox
keystone agent stop

# Stop with sync
keystone agent stop --sync

# Force stop specific sandbox
keystone agent stop --force myproject
```

**Exit Codes**:
- `0` - Sandbox stopped successfully
- `1` - Sandbox not found
- `2` - Stop failed (use --force)

---

### `keystone agent attach`

Attach to a running sandbox session.

**Usage**:
```bash
keystone agent attach [OPTIONS] [SANDBOX_NAME]
```

**Arguments**:
- `SANDBOX_NAME` - Name of sandbox (default: current project's sandbox)

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--worktree` | string | main | Worktree to attach to |
| `--web` | flag | false | Open in browser instead of terminal |

**Examples**:
```bash
# Attach to current project's sandbox
keystone agent attach

# Attach to specific worktree
keystone agent attach --worktree feature-branch

# Open in browser
keystone agent attach --web
```

**Exit Codes**:
- `0` - Attached successfully (returns on detach)
- `1` - Sandbox not found
- `2` - Sandbox not running

---

### `keystone agent sync`

Sync changes between sandbox and host.

**Usage**:
```bash
keystone agent sync [OPTIONS] [SANDBOX_NAME]
```

**Arguments**:
- `SANDBOX_NAME` - Name of sandbox (default: current project's sandbox)

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--artifacts` | flag | false | Also sync build artifacts via rsync |
| `--dry-run` | flag | false | Show what would be synced |
| `--branch` | string | current | Branch to sync |

**Examples**:
```bash
# Sync code changes
keystone agent sync

# Sync with artifacts
keystone agent sync --artifacts

# Dry run
keystone agent sync --dry-run
```

**Output**:
```text
Syncing from sandbox 'myproject'...
  Branch: feature-branch
  Commits: 3 new
  Files: 12 changed

Pulling changes...
  [===========================] 100%

Sync complete.
  Changed: 12 files
  Insertions: +234
  Deletions: -89
```

**Exit Codes**:
- `0` - Sync completed successfully
- `1` - Sandbox not found
- `2` - No changes to sync
- `3` - Merge conflict (resolve manually)

---

### `keystone agent worktree`

Manage git worktrees in the sandbox.

**Usage**:
```bash
keystone agent worktree <action> [OPTIONS] [ARGUMENTS]
```

**Actions**:

#### `keystone agent worktree add`
```bash
keystone agent worktree add <BRANCH> [--create]
```
- `BRANCH` - Branch name for worktree
- `--create` - Create branch if it doesn't exist

#### `keystone agent worktree list`
```bash
keystone agent worktree list
```

#### `keystone agent worktree remove`
```bash
keystone agent worktree remove <BRANCH> [--force]
```

**Examples**:
```bash
# Add worktree for existing branch
keystone agent worktree add feature-branch

# Create new branch and worktree
keystone agent worktree add new-feature --create

# List all worktrees
keystone agent worktree list

# Remove worktree
keystone agent worktree remove feature-branch
```

**Output** (list):
```text
Worktrees in sandbox 'myproject':

  BRANCH            PATH                              SESSION
  ─────────────────────────────────────────────────────────────
  main*             /workspace                        myproject-main
  feature-auth      /workspace/.worktrees/feature-auth    myproject-feature-auth
  bugfix-123        /workspace/.worktrees/bugfix-123      myproject-bugfix-123

* = current worktree
```

---

### `keystone agent status`

Show sandbox status.

**Usage**:
```bash
keystone agent status [OPTIONS] [SANDBOX_NAME]
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--json` | flag | false | Output as JSON |
| `--all` | flag | false | Show all sandboxes |

**Examples**:
```bash
# Current sandbox status
keystone agent status

# All sandboxes
keystone agent status --all

# JSON output
keystone agent status --json
```

**Output**:
```text
Sandbox: myproject
  State: running
  Uptime: 2h 34m
  Backend: microvm

Resources:
  Memory: 8192 MB (used: 4.2 GB)
  vCPUs: 4
  Disk: 20 GB (used: 8.1 GB)

Network:
  SSH: localhost:2222
  Dev servers:
    - myproject.sandbox.local:3000 -> :3000 (running)
    - myproject.sandbox.local:8080 -> :8080 (running)

Worktrees: 3
  main, feature-auth, bugfix-123

Last sync: 15 minutes ago
  Pending commits: 2
```

---

### `keystone agent list`

List all sandboxes.

**Usage**:
```bash
keystone agent list [OPTIONS]
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--json` | flag | false | Output as JSON |
| `--state` | enum | all | Filter by state |

**Output**:
```text
SANDBOX           STATE      BACKEND    UPTIME      PROJECT
────────────────────────────────────────────────────────────
myproject         running    microvm    2h 34m      ~/projects/myapp
other-project     stopped    microvm    -           ~/projects/other
```

---

### `keystone agent destroy`

Remove a sandbox completely.

**Usage**:
```bash
keystone agent destroy [OPTIONS] <SANDBOX_NAME>
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--force` | flag | false | Skip confirmation |
| `--keep-disk` | flag | false | Keep disk image |

**Examples**:
```bash
# Destroy with confirmation
keystone agent destroy myproject

# Force destroy
keystone agent destroy --force myproject
```

---

### `keystone agent exec`

Execute a command inside the sandbox.

**Usage**:
```bash
keystone agent exec [OPTIONS] [SANDBOX_NAME] -- <COMMAND>
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--worktree` | string | main | Worktree to run in |
| `--user` | string | agent | User to run as |

**Examples**:
```bash
# Run command in current sandbox
keystone agent exec -- npm test

# Run in specific worktree
keystone agent exec --worktree feature-branch -- make build

# Run in specific sandbox
keystone agent exec myproject -- git status
```

---

### `keystone agent ssh`

SSH directly into the sandbox.

**Usage**:
```bash
keystone agent ssh [OPTIONS] [SANDBOX_NAME]
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--port` | int | auto | SSH port (auto-detected) |

**Examples**:
```bash
# SSH to current sandbox
keystone agent ssh

# SSH to specific sandbox
keystone agent ssh myproject
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `KEYSTONE_AGENT_BACKEND` | Default backend (microvm, kubernetes) |
| `KEYSTONE_AGENT_MEMORY` | Default memory in MB |
| `KEYSTONE_AGENT_VCPUS` | Default vCPU count |
| `KEYSTONE_AGENT_SYNC_MODE` | Default sync mode |

## Configuration File

Location: `~/.config/keystone/agent.toml`

```toml
[defaults]
memory = 8192
vcpus = 4
nested_virt = true
sync_mode = "manual"
persist = true

[backend]
type = "microvm"

[backend.microvm]
share_proto = "virtiofs"

[proxy]
enable = true
domain = "sandbox.local"
```

## Exit Code Summary

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Resource not found |
| 2 | Invalid state for operation |
| 3 | Operation failed |
| 4 | System requirements not met |
| 5 | User cancelled |
