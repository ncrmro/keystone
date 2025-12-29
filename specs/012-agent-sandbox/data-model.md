# Data Model: Agent Sandbox

**Branch**: `012-agent-sandbox` | **Date**: 2025-12-24

This document defines the core entities, their relationships, validation rules, and state transitions for the Agent Sandbox system.

## Entity Overview

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Host System                                     │
│                                                                              │
│  ┌──────────────┐     creates      ┌──────────────┐                         │
│  │   Project    │─────────────────>│   Sandbox    │                         │
│  │  (git repo)  │                  │  (MicroVM)   │                         │
│  └──────────────┘                  └──────┬───────┘                         │
│         │                                 │                                  │
│         │ syncs to                        │ contains                         │
│         ▼                                 ▼                                  │
│  ┌──────────────┐                  ┌──────────────┐     manages             │
│  │   Worktree   │<─────────────────│  Workspace   │────────────┐            │
│  │  (host git)  │                  │ (/workspace) │            │            │
│  └──────────────┘                  └──────────────┘            │            │
│                                           │                    │            │
│  ┌──────────────┐                         │ hosts              │            │
│  │    Proxy     │<────────────────────────┼────────────────────┤            │
│  │   (Caddy)    │                         │                    │            │
│  └──────────────┘                         ▼                    ▼            │
│                                    ┌──────────────┐     ┌──────────────┐    │
│                                    │   Session    │     │   Backend    │    │
│                                    │  (Zellij)    │     │  (microvm)   │    │
│                                    └──────────────┘     └──────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Entities

### 1. Sandbox

The primary isolated execution environment.

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier (UUID or project-based) |
| `name` | string | Yes | Human-readable name (derived from project) |
| `project_path` | path | Yes | Absolute path to host git repository |
| `state` | enum | Yes | Lifecycle state |
| `backend` | enum | Yes | Runtime backend ("microvm" or "kubernetes") |
| `created_at` | timestamp | Yes | Creation time |
| `started_at` | timestamp | No | Last start time |
| `config` | SandboxConfig | Yes | Resource configuration |
| `ports` | map[string]int | No | Mapped ports (SSH, dev servers) |

**Validation Rules**:
- `project_path` must be a valid git repository
- `name` must be unique across active sandboxes
- `config.memory` >= 1024 (1GB minimum)
- `config.vcpus` >= 1

**State Transitions**:

```text
             create()
    ○ ─────────────────> [created]
                             │
                             │ start()
                             ▼
                        [starting]
                             │
                        ┌────┴────┐
                   success    failure
                        │         │
                        ▼         ▼
                    [running]  [error]
                        │         │
                   stop()     retry() or destroy()
                        │         │
                        ▼         │
                   [stopping]     │
                        │         │
                        ▼         │
                   [stopped] <────┘
                        │
                   destroy()
                        │
                        ▼
                       ○ (removed)
```

**Valid State Transitions**:
- `created` -> `starting` (via start)
- `starting` -> `running` (success) | `error` (failure)
- `running` -> `stopping` (via stop)
- `stopping` -> `stopped` (success)
- `stopped` -> `starting` (via start) | destroyed (via destroy)
- `error` -> `starting` (retry) | destroyed (via destroy)

---

### 2. SandboxConfig

Resource and behavior configuration for a sandbox.

**Fields**:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `memory` | int | 8192 | RAM in MB |
| `vcpus` | int | 4 | Virtual CPU count |
| `nested_virt` | bool | true | Enable nested virtualization |
| `network` | enum | "nat" | Network mode |
| `sync_mode` | enum | "manual" | Sync trigger mode |
| `sync_idle_seconds` | int | 30 | Idle timeout for auto-idle sync |
| `env_files` | list[string] | [".env*"] | Glob patterns for env files |
| `persist` | bool | true | Persist sandbox between sessions |

**Enums**:
- `network`: "nat" | "none" | "bridge"
- `sync_mode`: "manual" | "auto-commit" | "auto-idle"

---

### 3. Workspace

The `/workspace/` directory inside the sandbox.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `sandbox_id` | string | Parent sandbox |
| `root_path` | path | Always `/workspace` inside VM |
| `main_worktree` | Worktree | Primary clone of project |
| `worktrees` | map[string]Worktree | Additional worktrees by branch |
| `git_remote` | string | Host git remote URL |

**Directory Structure**:
```text
/workspace/
├── .git/                    # Main repository
├── <project files>          # Main worktree
└── .worktrees/
    ├── feature-branch-1/    # Worktree 1
    └── feature-branch-2/    # Worktree 2
```

**Validation Rules**:
- `root_path` must be `/workspace`
- `git_remote` must be valid git URL (local or SSH)
- Worktree names must be valid git branch names

---

### 4. Worktree

A git worktree for parallel branch development.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `branch` | string | Git branch name |
| `path` | path | Absolute path in sandbox |
| `is_main` | bool | True if main worktree |
| `session` | Session | Associated Zellij session |
| `dev_server_port` | int | Port for dev server (if running) |

**Validation Rules**:
- `branch` must be a valid git ref
- `path` must be under `/workspace/` or `/workspace/.worktrees/`
- Only one worktree per branch

---

### 5. Session

A Zellij terminal session attached to a worktree.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Zellij session name |
| `worktree` | Worktree | Associated worktree |
| `web_port` | int | WebSocket server port |
| `clients` | int | Connected client count |
| `created_at` | timestamp | Session creation time |

**Naming Convention**:
- Session ID: `<sandbox-name>-<branch>` (e.g., `myproject-main`)

**Validation Rules**:
- Session ID must be unique within sandbox
- `web_port` must be in range 1024-65535

---

### 6. Backend

The runtime provider that manages sandbox lifecycle.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `type` | enum | "microvm" or "kubernetes" |
| `config` | BackendConfig | Backend-specific configuration |

**MicroVM Backend Config**:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `qemu_extra_args` | list[string] | [] | Additional QEMU arguments |
| `share_proto` | enum | "virtiofs" | File share protocol |

**Kubernetes Backend Config** (future):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `context` | string | "" | kubectl context |
| `namespace` | string | "agent-sandboxes" | K8s namespace |
| `storage_class` | string | "standard" | PVC storage class |

---

### 7. Proxy

Host-side reverse proxy for dev server routing.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `sandbox_id` | string | Associated sandbox |
| `routes` | map[string]Route | Hostname to upstream mapping |

**Route**:

| Field | Type | Description |
|-------|------|-------------|
| `hostname` | string | e.g., `myproject.sandbox.local` |
| `upstream` | string | e.g., `localhost:8080` |
| `port` | int | External port (usually 80/443) |

---

## Relationships

```text
Sandbox 1──* Worktree     (sandbox contains worktrees)
Worktree 1──1 Session     (worktree has one session)
Sandbox 1──1 Workspace    (sandbox has one workspace)
Sandbox 1──1 Backend      (sandbox uses one backend)
Sandbox 1──* Route        (sandbox has multiple proxy routes)
```

## Persistence

**Ephemeral** (recreated each session):
- Session (Zellij state)
- Route (Caddy config)

**Persisted** (survives sandbox restart):
- Sandbox metadata (SQLite or JSON file)
- Workspace files (VM disk image)
- Worktree git state

**Host-Side State Location**:
```text
~/.config/keystone/agent/
├── sandboxes.json        # Sandbox registry
├── <sandbox-id>/
│   ├── config.json       # SandboxConfig
│   ├── disk.qcow2        # Persistent VM disk (if persist=true)
│   └── logs/
│       └── boot.log      # VM boot logs
```

## NixOS Module Options Mapping

```nix
keystone.agent = {
  # Sandbox defaults
  defaults = {
    memory = 8192;          # SandboxConfig.memory
    vcpus = 4;              # SandboxConfig.vcpus
    nestedVirt = true;      # SandboxConfig.nested_virt
    network = "nat";        # SandboxConfig.network
    syncMode = "manual";    # SandboxConfig.sync_mode
    persist = true;         # SandboxConfig.persist
  };

  # Backend selection
  backend = "microvm";      # Backend.type

  # Backend-specific
  microvm.shareProto = "virtiofs";  # MicroVM.share_proto
  kubernetes.context = "";          # K8s.context
  kubernetes.namespace = "agent-sandboxes";  # K8s.namespace

  # Proxy
  proxy = {
    enable = true;
    domain = "sandbox.local";  # Route.hostname suffix
  };
};
```
