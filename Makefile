.DEFAULT_GOAL := help

.PHONY: help ci fmt check-lockfile vm-server vm-test vm-ssh vm-connect vm-stop vm-clean

help: ## Show this help message
	@echo "Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

ci: ## Run CI checks (format + lockfile verification)
	$(MAKE) fmt
	$(MAKE) check-lockfile

fmt: ## Format Nix files
	nix fmt -- **/*.nix

check-lockfile: ## Verify flake.lock is up to date
	@echo "Checking if flake.lock is up to date..."
	@if ! git diff --quiet flake.lock; then \
		echo "Error: flake.lock has uncommitted changes"; \
		exit 1; \
	fi
	@nix flake check --no-build
	@echo "Lockfile verification passed"

## VM Testing Targets

vm-server: ## Launch VM with quickemu (manual workflow)
	@command -v quickemu >/dev/null 2>&1 || (echo "❌ Error: quickemu not found. Install with: nix-env -iA nixpkgs.quickemu" && exit 1)
	@test -f vms/keystone-installer.iso || (echo "❌ Error: vms/keystone-installer.iso not found. Run ./bin/build-iso first" && exit 1)
	@mkdir -p vms/server
	cd vms && quickemu --vm server.conf

vm-test: ## Build ISO with SSH key and launch VM (automated workflow)
	@command -v quickemu >/dev/null 2>&1 || (echo "❌ Error: quickemu not found. Install with: nix-env -iA nixpkgs.quickemu" && exit 1)
	@command -v nc >/dev/null 2>&1 || (echo "⚠️  Warning: netcat not found, SSH readiness check may fail" >&2)
	@echo "🔨 Building ISO with SSH key..."
	@if [ -z "$$SSH_KEY" ]; then \
		if [ -f ~/.ssh/id_ed25519.pub ]; then \
			./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub; \
		elif [ -f ~/.ssh/id_rsa.pub ]; then \
			./bin/build-iso --ssh-key ~/.ssh/id_rsa.pub; \
		else \
			echo "❌ Error: No SSH key found. Set SSH_KEY or create ~/.ssh/id_ed25519.pub"; \
			exit 1; \
		fi \
	else \
		./bin/build-iso --ssh-key "$$SSH_KEY"; \
	fi
	@if pgrep -f "qemu.*server.conf" > /dev/null; then \
		echo "⚠️  VM already running (PID: $$(pgrep -f 'qemu.*server.conf'))"; \
		echo "   Stop it with: make vm-stop"; \
		exit 1; \
	fi
	@if nc -z localhost 22220 2>/dev/null; then \
		echo "⚠️  Port 22220 already in use. Try another port or stop conflicting process"; \
		echo "   Check with: lsof -i :22220"; \
		exit 1; \
	fi
	@echo "🚀 Launching VM..."
	@mkdir -p vms/server
	@cd vms && quickemu --vm server.conf --display none &
	@echo "⏱️  Waiting for SSH (port 22220)..."
	@for i in $$(seq 1 30); do \
		if nc -z localhost 22220 2>/dev/null; then \
			echo "✅ VM ready!"; \
			echo ""; \
			echo "📡 Connect to VM:"; \
			echo "   ssh -p 22220 root@localhost"; \
			echo "   OR: make vm-connect"; \
			echo ""; \
			echo "ℹ️  Show connection: make vm-ssh"; \
			echo "🛑 Stop with: make vm-stop"; \
			echo "🧹 Clean artifacts: make vm-clean"; \
			exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "⚠️  SSH not available after 30 seconds. Check VM status:"; \
	echo "   ps aux | grep qemu"; \
	echo "   Check logs: tail -f vms/server/server.log (if exists)"; \
	exit 1

vm-ssh: ## Show SSH connection command
	@if ! pgrep -f "qemu.*server.conf" > /dev/null; then \
		echo "⚠️  VM not running. Start with: make vm-server or make vm-test"; \
		exit 1; \
	fi
	@if nc -z localhost $${SSH_PORT:-22220} 2>/dev/null; then \
		echo "✅ VM is ready"; \
		echo ""; \
		echo "📡 SSH connection:"; \
		echo "   ssh -p $${SSH_PORT:-22220} root@localhost"; \
	else \
		echo "⚠️  VM is running but SSH not ready yet"; \
		echo "   Wait a moment and try again"; \
	fi

vm-connect: ## Connect to VM via SSH
	@if ! pgrep -f "qemu.*server.conf" > /dev/null; then \
		echo "⚠️  VM not running. Start with: make vm-server or make vm-test"; \
		exit 1; \
	fi
	@if ! nc -z localhost $${SSH_PORT:-22220} 2>/dev/null; then \
		echo "⚠️  VM is running but SSH not ready yet. Wait a moment and try again."; \
		exit 1; \
	fi
	@ssh -p $${SSH_PORT:-22220} root@localhost

vm-stop: ## Stop the VM
	@if pgrep -f "qemu.*server.conf" > /dev/null; then \
		echo "🛑 Stopping VM..."; \
		pkill -f "qemu.*server.conf"; \
		sleep 2; \
		if pgrep -f "qemu.*server.conf" > /dev/null; then \
			echo "⚠️  VM still running, force killing..."; \
			pkill -9 -f "qemu.*server.conf"; \
		fi; \
		echo "✅ VM stopped"; \
	else \
		echo "ℹ️  No VM running"; \
	fi

vm-clean: ## Clean VM artifacts
	@if [ "$$FORCE" = "1" ] && pgrep -f "qemu.*server.conf" > /dev/null; then \
		echo "🛑 Stopping VM first..."; \
		$(MAKE) vm-stop; \
	elif pgrep -f "qemu.*server.conf" > /dev/null; then \
		echo "⚠️  VM is running. Stop it first with 'make vm-stop' or use 'FORCE=1 make vm-clean'"; \
		exit 1; \
	fi
	@echo "🧹 Cleaning VM artifacts..."
	@rm -f vms/server/*.qcow2 vms/server/*.fd vms/server/*.pid vms/server/*.log vms/server/*.ports vms/server/*.socket 2>/dev/null || true
	@if [ -d vms/server ] && [ -z "$$(ls -A vms/server 2>/dev/null)" ]; then \
		rmdir vms/server 2>/dev/null || true; \
	fi
	@echo "✅ Cleanup complete"