# CI Testing Infrastructure

This document describes the GitHub Actions CI testing infrastructure for Keystone.

## Current CI Coverage

The `.github/workflows/test.yml` workflow provides comprehensive test automation:

### Always-On Jobs

These jobs run on every pull request:

| Job | What it does |
|-----|--------------|
| `flake-check` | Main flake validation (`nix flake check`) |
| `critical-tests` | **Phase 1 critical tests** (see below) |

### Conditional Jobs

These jobs run only when specific files change:

| Job | Trigger | What it does |
|-----|---------|--------------|
| `iso-build` | ISO-related files | Dry-run ISO build verification |
| `installer-test` | Installer changes | Full TUI test with KVM |

## Phase 1: Critical Tests (Active)

The `critical-tests` job runs on every PR and includes:

1. **Formatting Check** (`nix fmt -- --check .`)
   - Ensures all Nix files follow consistent formatting
   - Prevents code style drift across PRs

2. **Test Flake Validation** (`nix flake check ./tests --no-build`)
   - Validates test configurations without building
   - Catches test configuration errors early

3. **Template Validation** (`cd templates/default && nix flake check --no-build`)
   - Ensures the flake template remains valid
   - Critical for user onboarding and quick start

4. **OS Module Evaluation** (`nix build ./tests#test-os-evaluation --no-link`)
   - Tests that core OS module options evaluate correctly
   - Catches breaking changes to module configuration

## Phase 2 & 3: Future Tests (Commented Out)

Additional tests are defined but commented out in the workflow. These can be enabled as needed:

### Phase 2: Module Tests

Path-filtered tests for module isolation:

```yaml
# desktop-isolation
#   Trigger: modules/desktop/**, modules/os/users.nix
#   Command: nix build ./tests#test-desktop-isolation --no-link

# server-isolation
#   Trigger: modules/server/**
#   Command: nix build ./tests#test-server-isolation --no-link

# terminal-test
#   Trigger: modules/terminal/**, tests/flake.nix
#   Command: nix build ./tests#homeConfigurations.testuser.activationPackage --no-link
```

### Phase 3: Integration Tests

Advanced tests requiring KVM support:

```yaml
# microvm-tpm
#   Trigger: modules/os/tpm.nix, modules/os/storage.nix, modules/os/secure-boot.nix
#   Command: ./bin/test-microvm-tpm

# microvm-agent
#   Trigger: modules/keystone/agent/**, packages/keystone-agent/**
#   Command: ./bin/test-microvm-agent

# remote-unlock
#   Trigger: modules/os/remote-unlock.nix
#   Command: nix build ./tests#test-remote-unlock --no-link
```

## Enabling Additional Tests

To enable Phase 2 or Phase 3 tests:

1. **Uncomment the job definition** in `.github/workflows/test.yml`
   - Find the job under the "Phase 2" or "Phase 3" section
   - Remove the `#` comment markers from the job

2. **Uncomment the output filter** in the `changes` job
   - Find the corresponding output line (e.g., `# desktop: ${{ steps.filter.outputs.desktop }}`)
   - Remove the `#` comment marker

3. **Uncomment the path filter** in the `changes` job
   - Find the corresponding filter definition under `filters:`
   - Remove the `#` comment markers from all lines in that filter

### Example: Enabling Desktop Tests

```yaml
# In the changes job outputs section:
outputs:
  desktop: ${{ steps.filter.outputs.desktop }}  # Uncomment this line

# In the filters section:
filters: |
  desktop:                                       # Uncomment this block
    - 'modules/desktop/**'
    - 'modules/os/users.nix'
    - 'tests/module/desktop-isolation.nix'

# Uncomment the desktop-isolation job:
desktop-isolation:
  needs: changes
  if: needs.changes.outputs.desktop == 'true'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: cachix/install-nix-action@v31
      with:
        nix_path: nixpkgs=channel:nixos-unstable
    - name: Test desktop isolation
      run: nix build ./tests#test-desktop-isolation --no-link
```

## Test Infrastructure

All tests are defined in the `tests/` directory:

- **`tests/flake.nix`** - Test configurations and checks
- **`tests/module/`** - Module isolation tests
- **`tests/integration/`** - Integration tests
- **`tests/microvm/`** - MicroVM test configurations
- **`bin/run-tests`** - Local test runner script

### Running Tests Locally

```bash
# Run all tests
make test

# Run specific test categories
make test-checks        # Fast flake validation
make test-module        # Module isolation tests
make test-integration   # Integration tests

# Or use the test runner directly
./bin/run-tests all
./bin/run-tests checks
./bin/run-tests test-desktop-isolation
```

## Path Filter Design

Path filters minimize CI time by only running tests when related files change:

- **Broad patterns** (`modules/desktop/**`) catch all changes in a module
- **Specific files** (`modules/os/users.nix`) target known dependencies
- **Test files** (`tests/module/desktop-isolation.nix`) trigger on test changes

This approach balances coverage with CI performance.

## GitHub Actions Features

### KVM Support

GitHub Actions runners support nested virtualization, enabling:
- NixOS VM tests
- MicroVM tests with TPM emulation
- Full integration testing with hardware features

Tests requiring KVM include an "Enable KVM" step:

```yaml
- name: Enable KVM
  run: |
    echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger --name-match=kvm
```

### Nix Installation

All jobs use `cachix/install-nix-action@v31` for consistent Nix installation with Nixpkgs channel `nixos-unstable`.

## Future Enhancements

Potential improvements not yet implemented:

- **Cachix caching** - 5-10x faster builds with binary cache
- **Main branch testing** - Post-merge regression detection
- **Build-VM evaluation** - Validate fast VM configs
- **Scheduled updates** - Automated `nix flake update` PRs

## Related Documentation

- **Local Testing**: [testing-procedure.md](testing-procedure.md)
- **VM Testing**: [testing-vm.md](testing-vm.md)
- **Agent Testing**: [agent-sandbox.md](agent-sandbox.md)
