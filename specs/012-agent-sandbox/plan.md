# Implementation Plan: Agent Sandbox

**Branch**: `012-agent-sandbox` | **Date**: 2025-12-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/012-agent-sandbox/spec.md`

## Summary

Provide isolated MicroVM environments for AI coding agents (Claude Code, Gemini CLI) to operate autonomously without host security restrictions. The system uses host-initiated git sync for secure bidirectional file transfer, Zellij for terminal session management, and a pluggable backend architecture supporting future Kubernetes integration.

## Technical Context

**Language/Version**: Nix (NixOS Flakes), Bash/Python for CLI scripts
**Primary Dependencies**: microvm.nix (astro/microvm.nix), Zellij, QEMU, virtiofs/9p
**Storage**: Host git repo cloned to `/workspace/`, virtiofs mounts, ZFS on host
**Testing**: NixOS module tests, MicroVM tier tests, integration tests
**Target Platform**: NixOS x86_64-linux (with nested virtualization support optional)
**Project Type**: NixOS module + CLI tooling
**Performance Goals**: <30s sandbox launch (warm), <500ms TUI attach, <5s sync
**Constraints**: Host-initiated transfers only, no VM SSH access to host
**Scale/Scope**: Single-user local development, future K8s multi-user backend

### Existing Patterns to Leverage

1. **MicroVM Infrastructure**: `tests/microvm/` has working microvm.nix integration with QEMU
2. **CLI Tooling**: `bin/` contains Bash/Python scripts with color output, trap cleanup, health checks
3. **Worktree Management**: `bin/worktree` (395 lines Python) provides git worktree + port randomization pattern
4. **Build-VM Pattern**: `bin/build-vm` demonstrates VM lifecycle with auto-connect and persistent state
5. **Module Structure**: `modules/keystone/terminal/` shows home-manager module patterns

### Technology Decisions

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Sandbox Runtime | microvm.nix | Lightweight, NixOS-native, direct kernel boot |
| Terminal Mux | Zellij | Rust-based, WebSocket support, session persistence |
| File Share | virtiofs | Better performance than 9p, standard for microvms |
| Code Sync | git push/pull | Host-initiated, familiar workflow, audit trail |
| Artifact Sync | rsync | Efficient incremental, host-initiated |
| Dev Server Proxy | Caddy + Avahi | Dynamic API, mDNS resolution |
| CLI Framework | Python + Click | Existing pattern in bin/worktree, bin/virtual-machine |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Declarative Infrastructure ✅

- [x] Sandbox configuration defined as NixOS modules
- [x] Version controlled in git
- [x] Reproducible across hardware via Nix flakes
- [x] Auditable via git history

### II. Security by Default ✅

- [x] Process isolation via VM boundary (not container)
- [x] Filesystem isolation (only `/workspace/` shared)
- [x] Credential isolation (host SSH keys inaccessible)
- [x] Host-initiated transfers (VM cannot push to host)
- [ ] NOTE: No disk encryption inside sandbox (ephemeral/stateless OK)

### III. Modular Composability ✅

- [x] Self-contained `keystone.agent` NixOS module
- [x] Composable with existing terminal/desktop modules
- [x] Clear backend interface for pluggability
- [x] Independent enable/disable per feature

### IV. Hardware Agnostic ✅

- [x] Runs on any x86_64-linux with KVM support
- [x] Nested virtualization optional (detected at runtime)
- [x] Works on bare-metal and virtualized hosts

### V. Cryptographic Sovereignty ✅

- [x] API keys provided by user via .env files (rsync'd)
- [x] Ephemeral SSH keys generated inside sandbox
- [x] No vendor escrow of credentials

### Gate Status: **PASSED** - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/012-agent-sandbox/
├── plan.md              # This file
├── research.md          # Phase 0 output - technology decisions
├── data-model.md        # Phase 1 output - entity definitions
├── quickstart.md        # Phase 1 output - getting started guide
├── contracts/           # Phase 1 output - CLI interface spec
│   └── cli-spec.md      # Command interface definitions
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# CLI Tooling
bin/
├── agent                # Main CLI entrypoint (Python)
├── agent-sync           # Sync helper script
└── agent-proxy          # Dev server proxy manager

# NixOS Modules
modules/keystone/agent/
├── default.nix          # Module entrypoint with keystone.agent.* options
├── sync.nix             # Git/rsync sync services
├── proxy.nix            # Dev server proxy configuration
└── backends/
    ├── default.nix      # Backend interface abstraction
    ├── microvm.nix      # MicroVM backend implementation
    └── kubernetes.nix   # K8s backend stub (future)

# Guest NixOS Configuration
modules/keystone/agent/guest/
├── default.nix          # Guest OS entrypoint
├── agents.nix           # AI agent packages (claude-code, etc.)
├── tools.nix            # Development tools
├── zellij.nix           # Zellij session management
└── worktree.nix         # Git worktree support

# Home-Manager (optional TUI)
modules/keystone/agent/home/
└── tui.nix              # TUI client configuration

# Tests
tests/
├── microvm/
│   └── agent-sandbox.nix  # Sandbox boot + basic functionality
└── integration/
    └── agent-workflow.nix # Full sync workflow test
```

**Structure Decision**: NixOS module pattern following `modules/keystone/terminal/` as reference. CLI in `bin/` using Python+Click pattern from existing scripts.

## Complexity Tracking

No constitution violations requiring justification.

## Phase 0 Research Topics

1. **Dev Server Proxy**: Evaluate Caddy vs nginx vs custom solution for `*.sandbox.local` routing
2. **Zellij Web Session**: Research Zellij WebSocket interface for remote TUI attachment
3. **Backend Interface**: Define abstract interface for MicroVM/K8s backend switching
4. **Nested Virtualization**: Document CPU feature detection and passthrough configuration
5. **Sync Modes**: Design auto-sync triggers (inotify, git hooks, idle detection)

## Phase 1 Design Deliverables

1. **data-model.md**: Sandbox, Workspace, Worktree, Session, Backend entities
2. **contracts/cli-spec.md**: `keystone agent` subcommand interface
3. **quickstart.md**: Getting started with agent sandbox

---

## Post-Design Constitution Re-Evaluation

*Completed after Phase 1 design.*

### I. Declarative Infrastructure ✅ MAINTAINED
- Sandbox configuration via `keystone.agent.*` NixOS options
- CLI configuration via `~/.config/keystone/agent.toml`
- All state persisted in version-controllable formats

### II. Security by Default ✅ MAINTAINED
- VM isolation boundary stronger than container
- Host-initiated transfers only (FR-008)
- Ephemeral credentials inside sandbox
- No disk encryption in sandbox (acceptable: ephemeral workloads)

### III. Modular Composability ✅ MAINTAINED
- `keystone.agent` module independent of `keystone.os` and `keystone.desktop`
- Pluggable backend interface defined
- Clear separation: host modules, guest modules, CLI

### IV. Hardware Agnostic ✅ MAINTAINED
- Works on any x86_64-linux with KVM
- Nested virtualization detected at runtime, graceful degradation
- Resource requirements documented (minimum 4GB RAM, 2 vCPU)

### V. Cryptographic Sovereignty ✅ MAINTAINED
- User provides API keys via .env files
- No vendor escrow or external key management
- Ephemeral SSH keys generated per-session

### Post-Design Gate Status: **PASSED**

No constitution violations identified. Design is ready for task generation.

---

## Artifacts Generated

| Artifact | Status | Path |
|----------|--------|------|
| plan.md | Complete | `specs/012-agent-sandbox/plan.md` |
| research.md | Complete | `specs/012-agent-sandbox/research.md` |
| data-model.md | Complete | `specs/012-agent-sandbox/data-model.md` |
| cli-spec.md | Complete | `specs/012-agent-sandbox/contracts/cli-spec.md` |
| quickstart.md | Complete | `specs/012-agent-sandbox/quickstart.md` |
| tasks.md | Complete | `specs/012-agent-sandbox/tasks.md` |
