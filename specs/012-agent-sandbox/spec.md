# Feature Specification: Agent Sandbox

**Feature Branch**: `agent-sandbox`
**Created**: 2025-12-24
**Status**: Draft
**Input**: User description for isolated AI coding agent environments with great developer experience

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Launch Agent in Sandbox (Priority: P1)

A developer wants to run an AI coding agent (Claude Code, Gemini CLI, Codex) on their project without granting the agent access to their host filesystem, SSH keys, or credentials. They launch a sandbox, the agent works autonomously without permission prompts, and changes sync back to the host.

**Why this priority**: This is the core value proposition - secure, autonomous agent operation. Without this, there's no product.

**Independent Test**: Developer can run `keystone agent start` on any git repo, the agent works without prompts, and `git diff` on host shows the changes.

**Acceptance Scenarios**:

1. **Given** a git repository on the host, **When** the user runs `keystone agent start`, **Then** a sandbox launches with the repo cloned to `/workspace/` and an agent ready to accept tasks
2. **Given** a running sandbox, **When** the agent modifies files, **Then** changes are visible on the host after sync (explicit or automatic)
3. **Given** a running sandbox, **When** the user types a task, **Then** the agent executes without any permission prompts or confirmation dialogs

---

### User Story 2 - Interactive TUI Session (Priority: P1)

A developer wants a seamless terminal experience to interact with the sandbox - viewing agent output, running commands, and managing multiple worktrees. The TUI should feel like a native terminal, not a clunky VM console.

**Why this priority**: Developer experience is paramount. A powerful but frustrating tool won't be used.

**Independent Test**: Developer launches TUI, can attach to agent session, run arbitrary commands, and switch between worktrees without leaving the interface.

**Acceptance Scenarios**:

1. **Given** a running sandbox, **When** the user runs `keystone agent attach`, **Then** they see a TUI with the current agent session (via Zellij web session)
2. **Given** the TUI is open, **When** the user creates a new worktree, **Then** it appears at `/workspace/.worktrees/<branch>` and is selectable in the TUI
3. **Given** multiple worktrees exist, **When** the user switches between them, **Then** each has independent terminal sessions and agent state

---

### User Story 3 - Sync Changes Back to Host (Priority: P1)

A developer needs their agent's work to appear on the host system. The sync must be secure (host-initiated, no VM SSH key access) and support selective sync (code vs build artifacts vs secrets).

**Why this priority**: Without reliable sync, agent work is trapped in the VM. This completes the core workflow.

**Independent Test**: Agent makes commits inside sandbox, user runs sync, commits appear in host git log.

**Acceptance Scenarios**:

1. **Given** the agent has made commits in the sandbox, **When** the user runs `keystone agent sync`, **Then** changes are pulled to the host via `git pull` from the VM
2. **Given** build artifacts exist in the sandbox, **When** the user runs `keystone agent sync --artifacts`, **Then** artifacts are rsync'd to the host
3. **Given** the VM is running, **When** sync occurs, **Then** the VM never needs SSH keys to the host (host initiates all transfers)

---

### User Story 4 - Proxy Development Servers (Priority: P2)

A developer running a web app in the sandbox wants to access it from their host browser at a friendly URL like `myapp.sandbox.local` without manual port forwarding.

**Why this priority**: Essential for web development workflows but not blocking core agent functionality.

**Independent Test**: Agent starts a dev server on port 3000, user visits `http://myproject.sandbox.local` in host browser and sees the app.

**Acceptance Scenarios**:

1. **Given** the sandbox is running, **When** a process listens on a port inside the VM, **Then** it's automatically proxied to `<project>.sandbox.local:<port>` on the host
2. **Given** multiple worktrees have dev servers, **When** the user accesses different hostnames, **Then** each routes to the correct worktree's server
3. **Given** the sandbox stops, **When** the user tries to access the proxy, **Then** they get a clear "sandbox not running" error

---

### User Story 5 - DevContainer Compatibility (Priority: P3)

A developer with an existing `.devcontainer/devcontainer.json` wants to use it with the agent sandbox, leveraging the DevContainer ecosystem (VSCode, etc.).

**Why this priority**: Opens access to large ecosystem but requires more implementation. Design for it now, implement later.

**Independent Test**: Project with `.devcontainer/` config launches correctly in sandbox with specified tools installed.

**Acceptance Scenarios**:

1. **Given** a repo with `.devcontainer/devcontainer.json`, **When** sandbox starts, **Then** the container configuration is respected (features, extensions, settings)
2. **Given** a DevContainer config specifies port forwarding, **When** the sandbox runs, **Then** those ports are automatically proxied
3. **Given** VSCode is installed on host, **When** user runs `keystone agent open-vscode`, **Then** VSCode attaches to the sandbox using Remote Containers

---

### User Story 6 - Nested VM Support (Priority: P2)

A developer working on infrastructure projects (like Keystone itself) needs to run VMs inside the sandbox for testing. The sandbox must support one level of nested virtualization so agents can create and manage test VMs.

**Why this priority**: Critical for dogfooding - Keystone uses VMs extensively for testing. Without this, agents can't work on Keystone itself.

**Independent Test**: Inside sandbox, agent runs `bin/build-vm terminal` or creates a microvm, and it boots successfully.

**Acceptance Scenarios**:

1. **Given** a sandbox is running, **When** the agent creates a microvm inside it, **Then** the nested VM boots and runs correctly
2. **Given** nested virtualization is enabled, **When** the agent runs Keystone's test suite, **Then** VM-based tests pass
3. **Given** a nested VM is running, **When** the parent sandbox syncs, **Then** nested VM state is not affected

---

### User Story 7 - Kubernetes Pod Backend (Priority: P4)

A developer in a team environment wants sandboxes to run on a shared Kubernetes cluster rather than local microvms, enabling consistent environments across the team.

**Why this priority**: Enterprise/team use case. Pluggable backend architecture should support this but implementation deferred.

**Independent Test**: Same `keystone agent start` command works against k8s cluster when configured.

**Acceptance Scenarios**:

1. **Given** `keystone.backend = "kubernetes"` in config, **When** user starts a sandbox, **Then** a pod is created in the configured cluster
2. **Given** a k8s sandbox is running, **When** the user attaches, **Then** the TUI experience is identical to local microvm
3. **Given** a k8s pod sandbox, **When** sync runs, **Then** git/rsync operations work the same as local

---

### Edge Cases

- What happens when the VM crashes mid-task? (Agent session can be recovered from Zellij, uncommitted changes may be lost)
- How does sync handle merge conflicts? (Host-side git handles conflicts normally after pull)
- What if the project has uncommitted changes on host? (Warn user, require commit or stash before launch)
- What if the host runs out of disk space during sync? (Clear error, partial sync rolled back)
- What if the agent tries to access host SSH keys? (They don't exist in VM - only ephemeral keys generated inside)
- What if host CPU doesn't support nested virtualization? (Detect and warn at sandbox start, disable nested VM features)
- What if a nested VM exhausts sandbox resources? (Resource limits enforced, nested VM killed before sandbox destabilizes)

## Requirements *(mandatory)*

### Functional Requirements

**Core Sandbox**:
- **FR-001**: System MUST launch an isolated environment (MicroVM or container) that cannot access host filesystem except via explicit sync
- **FR-002**: System MUST clone the host repository into `/workspace/` inside the sandbox via `git push` (host initiates, VM receives)
- **FR-003**: System MUST provide AI coding agents (Claude Code, Gemini CLI, etc.) pre-installed and configured to run without permission prompts
- **FR-004**: System MUST support multiple worktrees at `/workspace/.worktrees/<branch>/`
- **FR-005**: Sandbox MUST NOT have access to host SSH keys, API tokens, or credentials unless explicitly synced via rsync
- **FR-026**: Sandbox state MUST persist by default between sessions; `--fresh` flag creates a new sandbox discarding previous state

**Sync & Transfer**:
- **FR-006**: System MUST sync code changes via host-initiated `git pull` from the VM (VM has no push access to host)
- **FR-007**: System MUST support rsync for secrets, build artifacts, and other non-git files (host-initiated)
- **FR-008**: System MUST ensure all transfers are host-initiated (VM cannot initiate connections to host)
- **FR-022**: Sync mode MUST be configurable (manual, auto-on-commit, auto-on-idle) with manual as default
- **FR-023**: System MUST sync .env files (.env, .env.local, .env.production, etc.) from host to sandbox via rsync
- **FR-024**: Sandbox MUST have direnv installed and configured to auto-load .env files in /workspace/

**Developer Experience**:
- **FR-009**: System MUST provide a TUI for session management (attach, detach, switch worktrees)
- **FR-010**: TUI MUST integrate with Zellij web sessions for terminal multiplexing
- **FR-011**: TUI MUST work both on host (as controller) and inside VM (as client) - satisfied by Zellij's native session management in guest
- **FR-012**: System MUST automatically proxy development servers to `<project>.sandbox.local` hostnames

**Backend Abstraction**:
- **FR-013**: System MUST abstract sandbox lifecycle behind a pluggable backend interface
- **FR-014**: System MUST implement MicroVM backend as the initial/default backend
- **FR-015**: Backend interface MUST be designed to support Kubernetes pods (implementation deferred)

**Nested Virtualization**:
- **FR-018**: Sandbox MUST support one level of nested virtualization (VMs inside the sandbox MicroVM)
- **FR-019**: System MUST enable KVM passthrough to sandbox when host CPU supports nested virtualization
- **FR-020**: System MUST detect and report nested virtualization capability at sandbox startup
- **FR-021**: Nested VMs MUST be resource-limited to prevent exhausting sandbox resources
- **FR-025**: Sandbox resource allocation MUST be configurable, defaulting to 8GB RAM and 4 vCPU

**DevContainer Compatibility**:
- **FR-016**: System SHOULD parse `.devcontainer/devcontainer.json` for environment configuration
- **FR-017**: System SHOULD support DevContainer features for common tooling installation

### Key Entities

- **Sandbox**: An isolated execution environment (MicroVM or pod) with a single project workspace. Lifecycle states: `created` (initialized), `starting` (provisioning), `running` (usable), `stopping` (shutting down), `stopped` (terminated), `error` (failed)
- **Workspace**: The `/workspace/` directory containing the cloned repo and `.worktrees/` folder
- **Worktree**: A git worktree at `/workspace/.worktrees/<branch>/` for parallel branch work
- **Backend**: The runtime provider (MicroVM, Kubernetes) that creates and manages sandboxes
- **Session**: A Zellij terminal session attached to a sandbox, multiplexed and persistent
- **Proxy**: Host-side reverse proxy routing `*.sandbox.local` to sandbox dev servers

## Clarifications

### Session 2025-12-24

- Q: Should sync be automatic, manual, or hybrid? → A: Configurable, defaults to manual
- Q: How should API keys be delivered to sandbox? → A: Use .env file patterns (.env, .env.local, .env.production) synced via rsync, with direnv auto-loading
- Q: What are default sandbox resource limits? → A: Configurable, defaults to 8GB RAM / 4 vCPU
- Q: What lifecycle states should a sandbox have? → A: starting, running, stopped, error
- Q: Should sandbox persist or start fresh between sessions? → A: Persist by default, opt-in fresh with `--fresh` flag

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can go from `keystone agent start` to agent executing tasks in under 30 seconds (warm cache: VM image cached locally, sandbox previously created with `persist=true`)
- **SC-002**: Agent operates without any permission prompts or confirmation dialogs during normal operation
- **SC-003**: Code changes sync to host in under 5 seconds for typical commits
- **SC-004**: TUI session attach latency is under 500ms
- **SC-005**: 100% of host credentials (SSH keys, API tokens in `~/.config/`) are inaccessible from within the sandbox
- **SC-006**: Dev server proxy adds less than 10ms latency to requests
- **SC-007**: Same CLI commands work identically across MicroVM and (future) Kubernetes backends
- **SC-008**: Nested VMs boot successfully inside sandbox on hosts with nested virtualization support
- **SC-009**: Keystone's own VM-based test suite passes when run by an agent inside a sandbox
