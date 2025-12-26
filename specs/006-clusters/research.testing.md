# Research: Cluster Testing Infrastructure

**Feature**: 006-clusters
**Date**: 2024-12-21
**Phase**: 0 - Spike

## Overview

This document defines the testing strategy for Keystone Clusters, extending the patterns from `specs/001-keystone-os/research.testing.md` for multi-node cluster validation.

## Testing Objectives

### Spike Validation (Phase 0)
1. **Headscale mesh connectivity** - All nodes can ping each other via WireGuard mesh
2. **Pre-auth key enrollment** - Workers automatically register with primer's Headscale
3. **k3s bootstrap** - Kubernetes API accessible on primer
4. **Service discovery** - Nodes can resolve each other by hostname

### Future Phases
- kubectl access from workers to primer's k3s API
- Worker nodes joining as k3s agents
- Storage layer (Ceph/Rook) deployment
- Observability stack validation

## Framework Selection

### NixOS Test Framework (Primary)

**Rationale**: Based on existing `remote-unlock.nix` pattern which proves multi-node testing works.

| Capability | Support | Notes |
|------------|---------|-------|
| Multi-node orchestration | ✅ | Up to 10+ nodes |
| Automatic network bridging | ✅ | No manual config needed |
| Python test scripting | ✅ | Full control over test flow |
| Interactive debugging | ✅ | `driverInteractive` mode |
| CI/CD integration | ⚠️ | In `packages` output due to IFD |

**Why not libvirt?**
- Slower iteration (~5min vs ~30s)
- Requires manual network configuration
- More complex setup for multi-node
- Reserved for full deployment testing later

### Test Execution

```bash
# Build and run test
nix build ./tests#cluster-headscale

# Interactive debugging
nix build ./tests#cluster-headscale.driverInteractive
./result/bin/nixos-test-driver
>>> start_all()
>>> primer.shell_interact()  # Drop into primer's shell
```

## Cluster Test Architecture

### Node Configuration

```
┌─────────────────────────────────────────────────────────────┐
│                    NixOS Test Network                        │
│                    (Automatic bridging)                      │
│                                                              │
│  ┌────────────────┐                                         │
│  │    PRIMER      │ ◄─── k3s server + Headscale in K8s     │
│  │  4GB RAM, 2CPU │                                         │
│  │  Port 6443 k8s │                                         │
│  │  Port 8080 hs  │                                         │
│  └───────┬────────┘                                         │
│          │                                                   │
│          │ Headscale mesh (WireGuard)                       │
│          │                                                   │
│  ┌───────┼───────────────────┬───────────────────┐         │
│  │       │                   │                   │         │
│  ▼       ▼                   ▼                   ▼         │
│ ┌────────────┐        ┌────────────┐      ┌────────────┐   │
│ │  WORKER1   │        │  WORKER2   │      │  WORKER3   │   │
│ │  2GB RAM   │        │  2GB RAM   │      │  2GB RAM   │   │
│ │  tailscale │        │  tailscale │      │  tailscale │   │
│ └────────────┘        └────────────┘      └────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Resource Requirements

| Node | RAM | CPU | Purpose |
|------|-----|-----|---------|
| primer | 4096 MB | 2 | k3s server + Headscale pod |
| worker1-3 | 2048 MB | 1 | Tailscale client |
| **Total** | **10 GB** | **5** | Full cluster test |

### Test Flow

```python
# Phase 1: Bootstrap primer
primer.start()
primer.wait_for_unit("k3s.service")
primer.wait_for_open_port(6443)

# Phase 2: Wait for Headscale
primer.succeed("kubectl wait --for=condition=ready pod -l app=headscale -n headscale-system --timeout=120s")

# Phase 3: Generate auth keys
auth_key = primer.succeed("kubectl exec -n headscale-system deploy/headscale -- headscale preauthkeys create ...")

# Phase 4: Bootstrap workers
for worker in [worker1, worker2, worker3]:
    worker.start()
    worker.wait_for_unit("tailscaled.service")
    worker.succeed(f"tailscale up --login-server=http://primer:8080 --authkey={auth_key}")

# Phase 5: Verify mesh
worker1.succeed("tailscale ping worker2")
worker2.succeed("tailscale ping worker3")
worker3.succeed("tailscale ping primer")
```

## Module Test Integration

### Tests Flake Output

```nix
# tests/flake.nix
{
  packages.x86_64-linux = {
    # Cluster test (not in checks due to IFD)
    cluster-headscale = import ./integration/cluster-headscale.nix {
      inherit pkgs lib;
      self = inputs.self;
    };
  };
}
```

### Main Flake Module Exports

```nix
# flake.nix
nixosModules = {
  cluster-primer = ./modules/cluster/primer;
  cluster-worker = ./modules/cluster/worker;
  # ... existing modules
};
```

## Test Scenarios

### Scenario 1: Basic Mesh Connectivity (Spike)

**Goal**: Verify Headscale mesh works with 4 nodes

**Steps**:
1. Primer starts k3s, deploys Headscale
2. Workers register with pre-auth keys
3. All nodes can `tailscale ping` each other

**Success Criteria**:
- [ ] All 4 nodes visible in `headscale nodes list`
- [ ] `tailscale ping` succeeds between all pairs
- [ ] Test completes in under 5 minutes

### Scenario 2: k3s API Access (Post-Spike)

**Goal**: Workers can run kubectl against primer

**Steps**:
1. Complete Scenario 1
2. Export kubeconfig from primer
3. Workers use kubeconfig to query API

**Success Criteria**:
- [ ] `kubectl get nodes` works from workers
- [ ] Workers see primer as k8s node

### Scenario 3: Worker Node Join (Post-Spike)

**Goal**: Workers join k3s cluster as agents

**Steps**:
1. Complete Scenario 2
2. Workers run `k3s agent` with Headscale IP
3. Verify all nodes in cluster

**Success Criteria**:
- [ ] `kubectl get nodes` shows all 4 nodes
- [ ] Pods can be scheduled on workers

## CI Integration

### GitHub Actions Considerations

```yaml
jobs:
  cluster-test:
    runs-on: ubuntu-latest
    steps:
      - uses: cachix/install-nix-action@v27
        with:
          extra_nix_config: |
            system-features = kvm

      - name: Run cluster test
        run: nix build ./tests#cluster-headscale --print-build-logs
```

**Notes**:
- Requires KVM support on GitHub runners
- Test is in `packages`, not `checks`, to avoid IFD issues
- Consider caching Nix store for faster builds

### Test Categories

| Category | Framework | CI? | Duration |
|----------|-----------|-----|----------|
| Flake check | `nix flake check` | ✅ Always | ~30s |
| Module eval | Nix evaluation | ✅ Always | ~10s |
| Single-node | NixOS test | ✅ On change | ~1min |
| **Cluster** | NixOS test | ⚠️ On change | ~5min |
| Full deploy | libvirt | ❌ Manual | ~20min |

## References

- [NixOS Test Framework](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)
- `specs/001-keystone-os/research.testing.md` - Base testing patterns
- `tests/integration/remote-unlock.nix` - Multi-node test template
- `modules/vpn/server.nix` - Headscale K8s deployment pattern
- `specs/006-clusters/research.headscale-networking.md` - ACL and mesh config
