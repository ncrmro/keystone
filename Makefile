.PHONY: ci fmt check-lockfile

ci: fmt check-lockfile

fmt:
	nix fmt -- **/*.nix

check-lockfile:
	@echo "Checking if flake.lock is up to date..."
	@if ! git diff --quiet flake.lock; then \
		echo "Error: flake.lock has uncommitted changes"; \
		exit 1; \
	fi
	@nix flake check --no-build
	@echo "Lockfile verification passed"