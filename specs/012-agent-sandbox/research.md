# Research: Agent Sandbox

**Branch**: `012-agent-sandbox` | **Date**: 2025-12-24

This document resolves all NEEDS CLARIFICATION items from the implementation plan.

## 1. Dev Server Proxy Solution

**Decision**: Caddy + Avahi

**Rationale**: Caddy provides the simplest configuration for wildcard subdomain routing with a built-in REST API for dynamic upstream management. Avahi handles mDNS resolution for `*.sandbox.local` without manual `/etc/hosts` entries.

**Alternatives Considered**:

| Solution | Wildcard Support | Dynamic Config | Complexity | Verdict |
|----------|-----------------|----------------|------------|---------|
| Caddy | Native matchers | REST API (zero-downtime) | Low | **Selected** |
| nginx | Via regex | Requires reload | Medium | Rejected - no dynamic API |
| Traefik | Excellent | File/HTTP providers | High | Rejected - overkill |
| systemd-socket-proxyd | N/A | Static only | Low | Rejected - no HTTP routing |

**Implementation Pattern**:
```text
1. Enable Avahi for *.sandbox.local mDNS resolution
2. Run Caddy reverse proxy on host
3. Use Caddy JSON API to register routes as VMs start
4. Route <project>.sandbox.local -> localhost:<vm-port>
```

**NixOS Integration**:
- `services.caddy` module for proxy configuration
- `services.avahi` module for mDNS (already used in Keystone)
- Dynamic route registration via Caddy API at `localhost:2019`

**Sources**:
- [Caddy API Documentation](https://caddyserver.com/docs/api)
- [Caddy on NixOS Wiki](https://wiki.nixos.org/wiki/Caddy)
- [Traefik on NixOS](https://wiki.nixos.org/wiki/Traefik)

---

## 2. Zellij Web Session Architecture

**Decision**: Use Zellij's built-in web server with WebSocket connections

**Rationale**: Zellij has native web client support via `zellij web` command. The web client uses xterm.js in the browser and communicates through bidirectional WebSocket channels, providing the same experience as terminal clients.

**Key Features**:
- **URL-based session access**: Sessions accessible at `https://127.0.0.1/<session-name>`
- **Dual WebSocket channels**: Terminal (STDIN/STDOUT) + Control (resize, config, logs)
- **Multi-client support**: Browser and terminal clients appear as regular users
- **Authentication**: Token-based middleware protects WebSocket routes
- **Session persistence**: Workspaces maintained after disconnection

**Implementation Pattern**:
```text
1. Start Zellij web server inside sandbox: zellij web --port 8080
2. Proxy via Caddy: agent-<project>.sandbox.local -> VM:8080
3. User accesses TUI via browser or dedicated client
4. Sessions persist across disconnects
```

**Integration with Agent Sandbox**:
- Start Zellij web server automatically on sandbox boot
- Register web server port with Caddy proxy
- Support both browser and terminal attachment modes
- Session names match worktree branches for easy navigation

**Sources**:
- [Zellij Web Client Tutorial](https://zellij.dev/tutorials/web-client/)
- [Building Zellij's Web Terminal](https://poor.dev/blog/building-zellij-web-terminal/)
- [Zellij Session Management](https://zellij.dev/tutorials/session-management/)

---

## 3. Backend Interface Design

**Decision**: Abstract backend interface with MicroVM as default implementation

**Rationale**: The spec requires pluggable backends (FR-013, FR-014, FR-015). Defining a clear interface now enables Kubernetes implementation later without refactoring.

**Interface Definition**:

```python
# Conceptual interface (implemented as NixOS module options + CLI)
class SandboxBackend:
    def create(project_path: str, config: SandboxConfig) -> SandboxID
    def start(sandbox_id: SandboxID) -> None
    def stop(sandbox_id: SandboxID) -> None
    def destroy(sandbox_id: SandboxID) -> None
    def status(sandbox_id: SandboxID) -> SandboxState
    def exec(sandbox_id: SandboxID, command: list[str]) -> ExecResult
    def get_ssh_port(sandbox_id: SandboxID) -> int
    def get_dev_server_ports(sandbox_id: SandboxID) -> dict[str, int]
```

**NixOS Module Options**:
```nix
keystone.agent = {
  enable = mkEnableOption "Agent sandbox support";
  backend = mkOption {
    type = types.enum [ "microvm" "kubernetes" ];
    default = "microvm";
    description = "Sandbox backend to use";
  };
  # Backend-specific options
  microvm = {
    memory = mkOption { type = types.int; default = 8192; };
    vcpus = mkOption { type = types.int; default = 4; };
  };
  kubernetes = {
    context = mkOption { type = types.str; default = ""; };
    namespace = mkOption { type = types.str; default = "agent-sandboxes"; };
  };
};
```

**State Machine**:
```text
[created] -> [starting] -> [running] -> [stopping] -> [stopped]
                |              |                          |
                v              v                          v
            [error]        [error]                    [destroyed]
```

---

## 4. Nested Virtualization Configuration

**Decision**: Enable KVM passthrough with runtime detection

**Rationale**: The spec requires nested VM support (FR-018, FR-019, FR-020) for Keystone dogfooding. Detection at startup allows graceful degradation.

**Host Configuration**:
```nix
# Enable nested virtualization on host
boot.extraModprobeConfig = ''
  options kvm_intel nested=1
  # or for AMD: options kvm_amd nested=1
'';
```

**Detection Script**:
```bash
# Check if nested virtualization is available
check_nested_virt() {
    local nested_file
    if [ -f /sys/module/kvm_intel/parameters/nested ]; then
        nested_file=/sys/module/kvm_intel/parameters/nested
    elif [ -f /sys/module/kvm_amd/parameters/nested ]; then
        nested_file=/sys/module/kvm_amd/parameters/nested
    else
        echo "KVM module not loaded"
        return 1
    fi

    if [ "$(cat $nested_file)" = "Y" ] || [ "$(cat $nested_file)" = "1" ]; then
        echo "Nested virtualization: enabled"
        return 0
    else
        echo "Nested virtualization: disabled"
        return 1
    fi
}
```

**MicroVM Guest Configuration**:
```nix
microvm = {
  qemu.extraArgs = [
    "-cpu" "host,+vmx"  # Pass through VMX capability
  ];
};
```

**Resource Limits for Nested VMs**:
- Parent sandbox: 8GB RAM, 4 vCPU (default)
- Nested VM limit: 4GB RAM, 2 vCPU (enforced via cgroups)
- Warn user if host doesn't support nesting

**Sources**:
- [microvm.nix GitHub](https://github.com/astro/microvm.nix)
- [NixOS Nested Virtualization](https://discourse.nixos.org/t/enabling-nested-virtualization-on-windows-11-vm-running-nixos-via-qemu-kvm/35755)
- [Fedora Nested KVM Docs](https://docs.fedoraproject.org/en-US/quick-docs/using-nested-virtualization-in-kvm/)

---

## 5. Sync Modes Implementation

**Decision**: Three sync modes with manual as default

**Rationale**: The spec requires configurable sync (FR-022). Different workflows benefit from different triggers.

**Sync Modes**:

| Mode | Trigger | Use Case |
|------|---------|----------|
| `manual` | `keystone agent sync` command | Default, explicit control |
| `auto-commit` | Git post-commit hook in sandbox | Immediate feedback |
| `auto-idle` | No activity for N seconds | Batch changes |

**Implementation Details**:

### Manual Sync
```bash
# Host initiates pull from VM
keystone agent sync [--artifacts]
# 1. SSH to VM, run: git push origin HEAD
# 2. Host: git pull origin <branch>
# 3. Optional: rsync artifacts
```

### Auto-Commit Sync
```bash
# Inside sandbox, post-commit hook triggers:
curl -X POST http://host.sandbox.local:8080/sync-notify
# Host-side daemon sees notification, initiates sync
```

### Auto-Idle Sync
```bash
# Sandbox runs idle detector:
inotifywait -m -r /workspace --format '%T' --timefmt '%s' \
  | awk -v idle=30 '{
      now=systime()
      if (now - last > idle) { system("notify-sync") }
      last=now
    }'
```

**Configuration**:
```nix
keystone.agent = {
  sync = {
    mode = mkOption {
      type = types.enum [ "manual" "auto-commit" "auto-idle" ];
      default = "manual";
    };
    idleSeconds = mkOption {
      type = types.int;
      default = 30;
      description = "Seconds of inactivity before auto-idle sync";
    };
  };
};
```

---

## 6. File Share Protocol

**Decision**: virtiofs for production, 9p for compatibility fallback

**Rationale**: virtiofs provides better performance but requires virtiofsd daemon. 9p works universally but with lower performance.

**Comparison**:

| Feature | virtiofs | 9p |
|---------|----------|-----|
| Performance | High | Medium |
| Setup complexity | Requires virtiofsd | Built into QEMU |
| NixOS support | Good (microvm.nix) | Native |
| macOS support | Limited | Better |

**Implementation**:
```nix
microvm.shares = [{
  tag = "workspace";
  source = "/path/to/project";
  mountPoint = "/workspace";
  proto = "virtiofs";  # Default
  # proto = "9p";      # Fallback
}];
```

---

## 7. Git Sync Security Model

**Decision**: Host-initiated transfers only, ephemeral VM credentials

**Rationale**: The spec requires VM cannot initiate connections to host (FR-008).

**Security Model**:
```text
┌─────────────────┐                    ┌─────────────────┐
│      Host       │                    │    Sandbox VM   │
│                 │                    │                 │
│  - SSH client   │───SSH tunnel──────>│  - git server   │
│  - git client   │<──git push─────────│  - workspace    │
│  - rsync client │───rsync pull──────>│  - artifacts    │
│                 │                    │                 │
│  NO inbound SSH │                    │  - ephemeral    │
│  from VM        │                    │    SSH keys     │
└─────────────────┘                    └─────────────────┘
```

**Credential Flow**:
1. VM generates ephemeral SSH keypair on boot
2. Public key displayed for user to add as deploy key (if needed)
3. Host SSH config uses `-o StrictHostKeyChecking=no` for VM
4. API keys delivered via .env rsync (host-initiated)

---

## Summary of Decisions

| Topic | Decision | Confidence |
|-------|----------|------------|
| Dev Server Proxy | Caddy + Avahi | High |
| Terminal Sessions | Zellij web server | High |
| Backend Interface | Abstract module options | High |
| Nested Virtualization | KVM passthrough with detection | High |
| Sync Modes | Manual/auto-commit/auto-idle | High |
| File Share | virtiofs (9p fallback) | High |
| Security Model | Host-initiated, ephemeral creds | High |

All NEEDS CLARIFICATION items resolved. Ready for Phase 1 design.
