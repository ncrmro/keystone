# Makefile Interface Contract: VM Testing

**Version**: 1.0.0
**Date**: 2025-10-17

## Overview

Simple Makefile-based interface for VM testing workflow, extending the existing `make vm-server` target from feat/quickemu-server.

## Makefile Targets

### Existing Target (from feat/quickemu-server)

```makefile
vm-server: ## Launch VM with quickemu
	cd vms && quickemu --vm server.conf
```

### New Targets

```makefile
vm-test: ## Build ISO with SSH key and launch VM
	@echo "🔨 Building ISO with SSH key..."
	./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
	@echo "🚀 Launching VM..."
	cd vms && quickemu --vm server.conf &
	@echo "⏱️  Waiting for SSH (port 22220)..."
	@for i in $$(seq 1 30); do \
		if nc -z localhost 22220 2>/dev/null; then \
			echo "✅ VM ready! Connect with: ssh -p 22220 root@localhost"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "⚠️  SSH not available after 30 seconds"

vm-ssh: ## Show SSH connection command
	@echo "ssh -p 22220 root@localhost"

vm-stop: ## Stop the VM (kills qemu process)
	@pkill -f "qemu.*server.conf" || echo "No VM running"

vm-clean: ## Clean VM artifacts
	rm -f vms/server/*.qcow2 vms/server/*.fd vms/server/*.pid vms/server/*.log
```

## Usage Examples

### Complete Test Workflow
```bash
# Build ISO and start VM with SSH
make vm-test

# In another terminal, connect via SSH
ssh -p 22220 root@localhost

# Stop the VM when done
make vm-stop

# Clean up artifacts
make vm-clean
```

### Manual Workflow (existing)
```bash
# Build ISO with SSH key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Start VM
make vm-server

# Connect via SSH
ssh -p 22220 root@localhost
```

## Environment Variables

```bash
# Custom SSH key
SSH_KEY=~/.ssh/custom_key.pub make vm-test

# Custom SSH port (requires server.conf edit)
SSH_PORT=2222 make vm-ssh
```

## Implementation Notes

- Builds on existing `vm-server` target
- Minimal new code - just Makefile targets
- Uses existing `bin/build-iso` script
- Leverages quickemu's built-in functionality
- Simple process management with pkill

## Files Affected

```
Makefile
├── vm-test   (new)
├── vm-ssh    (new)
├── vm-stop   (new)
├── vm-clean  (new)
└── vm-server (existing, unchanged)
```

## Future Enhancements

Once this simple interface is working, could add:
- `vm-status` to check if VM is running
- `vm-rebuild` to force ISO rebuild
- `vm-console` for serial console access