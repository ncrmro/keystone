# Research: Testing K3S VM Cluster Primer

**Date**: 2026-01-05  
**Agent**: Copilot Agent  
**Task**: Bring up k3s VMs to test the cluster primer

## Issues Encountered

### 1. Network Restriction - GitHub API Blocked

**Issue**: When trying to build the cluster-primer microVM, Nix attempted to fetch `microvm.nix` from GitHub but encountered:

```
error: unable to download 'https://api.github.com/repos/astro/microvm.nix/tarball/bb9e99bdb3662354299605cc1a75a2b1a86bd29a': HTTP error 403
response body: Blocked by DNS monitoring proxy
```

**Root Cause**: The sandbox environment blocks access to certain GitHub API endpoints via a DNS monitoring proxy.

**Impact**: Cannot build microVM configurations that depend on external flake inputs during testing.

**Attempted Workarounds**:
- [ ] Try using `--offline` mode with pre-downloaded inputs
- [ ] Check if inputs are already in the Nix store
- [ ] Use alternative build method without microvm.nix

### 2. MicroVM.nix Dependency

**Current State**: The test configuration at `tests/flake.nix` depends on:
```nix
microvm = {
  url = "github:astro/microvm.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Configuration Files**:
- Primer: `tests/microvm/cluster-primer.nix`
- Workers: `tests/microvm/cluster-worker.nix`
- Test script: `bin/test-cluster-microvm`

**Architecture**:
The cluster primer is designed to:
1. Run k3s server in a microVM with user-mode networking
2. Deploy Headscale inside k3s via manifests
3. Use agenix for secret management
4. Forward ports: SSH (22223), k3s API (16443), Headscale HTTP (18080)
5. Optionally join worker VMs via Tailscale

## Testing Results

### Alternative Test Approach: nixosTest

Since microvm.nix cannot be downloaded due to network restrictions, I pivoted to testing the existing integration test at `tests/integration/cluster-headscale.nix` which uses NixOS's built-in VM testing framework (`pkgs.testers.nixosTest`).

**Test Command**: `cd tests && nix build .#cluster-headscale`

**Test Progress**:
- ✅ k3s server started successfully on primer node
- ✅ k3s API server became ready on port 6443
- ✅ k3s-ready service completed
- ✅ Namespace and ConfigMap created successfully
- ❌ Headscale deployment failed with YAML parsing error

### Issue Found: YAML Template Substitution Bug

**Error**:
```
error: error parsing /nix/store/...-headscale-manifests.yaml: error converting YAML to JSON: yaml: line 66: did not find expected key
```

**Root Cause**: The headscale manifest template at `modules/cluster/primer/headscale-manifests.yaml` uses placeholder substitutions (`@@keysVolumeMounts@@`, `@@dataVolume@@`, `@@keysVolume@@`) that are replaced with multiline strings in `modules/cluster/primer/headscale.nix`.

When these substitutions contain newlines with specific indentation, they break the YAML structure. Looking at lines 98, 122-123 in the template:

```yaml
            - name: data
              mountPath: /var/lib/headscale
@@keysVolumeMounts@@              # Line 98 - can be empty or multiline
          resources:
      volumes:
        - name: config
          configMap:
            name: headscale-config
@@dataVolume@@                     # Line 122 - multiline volume definition
@@keysVolume@@                     # Line 123 - multiline when using agenix
```

The substitution in `headscale.nix` (lines 179-189) creates strings with embedded newlines and indentation that don't align properly with the surrounding YAML.

**Specific Problem**: When volumes are added at lines 122-123, they need proper indentation (8 spaces for volumes list items), but the current string substitution doesn't preserve YAML indentation rules consistently.

## Next Steps

1. **Fix YAML template substitution**: Correct the indentation in multiline string replacements
2. **Test the fix**: Re-run the cluster-headscale test
3. **Document worker node testing**: Once primer works, test worker registration
4. **Alternative: Use yq or similar**: Consider using a YAML templating tool instead of string replacement

## Recommendations

### Short-term (Testing in Restricted Environment)
- Pre-cache all flake inputs before testing
- Use `nix flake archive` to ensure all dependencies are available
- Consider using Docker/Podman containers as an alternative to microvm.nix

### Long-term (Cluster Testing Strategy)
- Add integration test that doesn't require network access
- Create a "offline testing mode" that uses pre-built artifacts
- Document network requirements for cluster testing

## Configuration Summary

### Cluster Primer Module
- **Location**: `modules/cluster/primer/`
- **Components**: k3s, Headscale deployment
- **Features**: 
  - Embedded k3s with disabled traefik
  - Headscale deployed as k8s workload
  - Agenix secret management integration
  - Port forwarding for external access

### Test Fixtures
- **Location**: `tests/fixtures/`
- **Contents**:
  - `test-age-key.txt` - Test age identity for agenix
  - `headscale-*.age` - Encrypted Headscale keys
  - `test-ssh-key.pub` - SSH key for VM access

### Expected Behavior
When functional, the test should:
1. Build primer VM with k3s and Headscale
2. Start VM and wait for k3s to be ready
3. Deploy Headscale to k3s
4. Optionally start worker VMs
5. Workers join the Headscale mesh
6. Verify connectivity via kubectl
