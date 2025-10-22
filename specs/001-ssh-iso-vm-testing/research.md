# Research: SSH-Enabled ISO with VM Testing

**Date**: 2025-10-17
**Feature**: SSH-Enabled ISO with VM Testing
**Branch**: `001-ssh-iso-vm-testing`

## Overview

This research document captures decisions and best practices for implementing VM lifecycle management and SSH testing workflows for Keystone ISOs.

## Key Decisions

### 1. VM Management Approach

**Decision**: Individual shell scripts for each VM operation
**Rationale**:
- Follows Unix philosophy of single-purpose tools
- Enables composition in workflows (pipes, scripts)
- Easier to test and debug individual operations
- Consistent with existing `bin/build-iso` pattern

**Alternatives considered**:
- Single monolithic VM management script: Rejected due to complexity and harder maintenance
- Python/Go tool: Rejected to avoid additional dependencies and maintain consistency with bash tooling

### 2. Process Management

**Decision**: Use PID files and quickemu's native process management
**Rationale**:
- quickemu already creates PID files (`server.pid`)
- Standard Unix approach for daemon management
- Easy to check if VM is running via PID existence and process validation

**Alternatives considered**:
- systemd services: Rejected as too complex for development VMs
- Docker containers: Rejected due to nested virtualization complexity

### 3. SSH Readiness Detection

**Decision**: Poll SSH port with timeout using `nc` (netcat) or native bash TCP
**Rationale**:
- Lightweight, no additional dependencies
- Bash supports `/dev/tcp` for simple port checking
- Clear success/failure semantics

**Alternatives considered**:
- SSH with retry loop: Rejected as it generates auth failures in logs
- VM guest agent: Rejected as too complex for simple testing

### 4. Port Conflict Handling

**Decision**: Check port availability before VM start, offer alternative ports
**Rationale**:
- Proactive error prevention
- Clear user feedback about conflicts
- Suggest next available port in range (22220-22229)

**Alternatives considered**:
- Random port selection: Rejected as unpredictable for users
- Fail fast only: Rejected as not user-friendly

### 5. Error Handling Strategy

**Decision**: Defensive scripting with clear error messages
**Rationale**:
- Set `-euo pipefail` for robust error handling
- Provide actionable error messages
- Exit codes follow conventions (0=success, 1=general error, 2=usage error)

**Best Practices**:
- Check preconditions early (quickemu installed, ISO exists)
- Clean up on failure (trap EXIT)
- Log verbose output to files for debugging

## Implementation Patterns

### Script Structure Template

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
VM_DIR="${VM_DIR:-vms}"
VM_NAME="${VM_NAME:-server}"
SSH_PORT="${SSH_PORT:-22220}"

# Colors for output (same as build-iso)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Error handling
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Precondition checks
check_dependencies() {
    command -v quickemu >/dev/null 2>&1 || error "quickemu not found"
}

# Main logic
main() {
    check_dependencies
    # Implementation here
}

main "$@"
```

### SSH Port Checking Pattern

```bash
check_ssh_ready() {
    local port=$1
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if (echo > /dev/tcp/localhost/$port) >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
```

### PID File Management Pattern

```bash
is_vm_running() {
    local pid_file="$VM_DIR/$VM_NAME/$VM_NAME.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}
```

## File Organization

### VM State Files

- **PID file**: `vms/server/server.pid` - Process ID for running VM
- **Ports file**: `vms/server/server.ports` - Port mappings (ssh,22220)
- **Log file**: `vms/server/server.log` - Console output for debugging
- **Monitor socket**: `vms/server/server-monitor.socket` - QEMU monitor
- **Serial socket**: `vms/server/server-serial.socket` - Serial console

### Script Responsibilities

1. **vm-start**: Launch VM, wait for boot, report status
2. **vm-stop**: Graceful shutdown via QEMU monitor
3. **vm-status**: Check running state, display connection info
4. **vm-ssh**: Show SSH command with correct options
5. **vm-clean**: Remove disk image and state files
6. **vm-test**: Orchestrate full workflow

## Integration Points

### Makefile Targets

Add complementary Makefile targets for common operations:

```makefile
.PHONY: vm-start vm-stop vm-status vm-clean vm-test

vm-start: ## Start the test VM
	./bin/vm-start

vm-stop: ## Stop the test VM
	./bin/vm-stop

vm-status: ## Check VM status
	./bin/vm-status

vm-clean: ## Clean VM artifacts
	./bin/vm-clean

vm-test: ## Run complete VM test workflow
	./bin/vm-test
```

### Documentation Integration

Update README with VM testing workflow:
- Quick start section showing `vm-test` usage
- Troubleshooting guide for common issues
- Port forwarding configuration options

## Security Considerations

1. **SSH Keys**: Never embed private keys, only public keys in ISO
2. **Port Exposure**: VM SSH port only on localhost by default
3. **VM Isolation**: quickemu provides good isolation via QEMU/KVM
4. **Clean Shutdown**: Always attempt graceful shutdown to prevent corruption

## Performance Optimizations

1. **ISO Caching**: Reuse existing ISO if no changes to SSH keys
2. **VM Snapshot**: Consider snapshot capability for quick reset
3. **Parallel Operations**: Status checks can run while VM boots
4. **Resource Limits**: Configure reasonable CPU/RAM limits in quickemu config

## Testing Strategy

### Manual Testing Checklist

- [ ] VM starts with valid ISO
- [ ] VM fails gracefully with missing ISO
- [ ] SSH connection works with embedded key
- [ ] SSH fails with wrong key
- [ ] Port conflict detected and reported
- [ ] Clean removes all artifacts
- [ ] Status accurate for running/stopped states
- [ ] Workflow completes end-to-end

### Automated Testing Approach

Future consideration: Shell script tests using `bats` framework
- Test individual script functions
- Mock quickemu for unit tests
- Integration tests with real VMs in CI

## Conclusion

The implementation follows established patterns from the existing codebase while adding robust VM lifecycle management. Focus on simplicity, clear error messages, and defensive programming ensures a reliable developer experience.