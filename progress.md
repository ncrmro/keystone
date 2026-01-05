# Progress: Cluster Testing - Headscale Key Fix

**Date**: 2026-01-05
**Feature**: 006-clusters
**Status**: In Progress

## Current Goal

Fix Headscale key format issue to enable cluster mesh networking testing.

## Context

The cluster-primer microVM testing revealed that Headscale expects 64-character hex strings for its noise/private keys, but the test fixtures contained WireGuard-style base64 keys (44 characters).

### Error Discovered
```
FTL Error initializing error="failed to read or create Noise protocol private key:
failed to parse private key: key hex has the wrong size, got 44 want 64"
```

## Completed Steps

### 1. ✅ SSH Key Integration (Previous Session)
- Added SSH key auth to `tests/microvm/cluster-primer.nix`
- Added SSH key auth to `tests/microvm/cluster-worker.nix`
- Updated `bin/test-cluster-microvm` to use key-based auth
- Created `tests/fixtures/README.md` documenting fixtures
- Committed: `feat(cluster): add SSH key auth for microVM testing`

### 2. ✅ MicroVM Validation (Previous Session)
- MicroVM boots in ~30 seconds
- SSH key authentication works
- k3s service starts successfully
- Agenix secrets decrypt to `/run/agenix/`
- Headscale fails due to key format (documented in plan.md and research.testing.md)

### 3. ✅ Generate Correct Hex Keys (This Session)
Generated 3 new keys with correct 64-char hex format:
```bash
openssl rand -hex 32 > headscale-private.key
openssl rand -hex 32 > headscale-noise.key
openssl rand -hex 32 > headscale-derp.key
```

### 4. ✅ Re-encrypt with Age (This Session)
Encrypted keys using the test age public key:
```bash
AGE_PUBKEY="age1u3f3r3h7m4rrl5dw97ee65fde38tfq0xk9ljdh5strf3z6a0js7q9g8hkj"
age -r "$AGE_PUBKEY" headscale-private.key > headscale-private.age
age -r "$AGE_PUBKEY" headscale-noise.key > headscale-noise.age
age -r "$AGE_PUBKEY" headscale-derp.key > headscale-derp.age
```

Verified decryption produces correct 64-char hex strings.

## Pending Steps

### 5. ⏳ Rebuild and Test MicroVM
```bash
cd /home/ncrmro/code/ncrmro/keystone/worktree/cluster-primer/tests
nix build .#nixosConfigurations.cluster-primer.config.microvm.declaredRunner -o result-primer
./result-primer/bin/microvm-run
```

Then verify:
- Headscale pod starts without CrashLoopBackOff
- `kubectl get pods -A` shows headscale-system pods healthy

### 6. ⏳ Test Full Cluster with Workers
```bash
./bin/test-cluster-microvm --workers
```

Validate:
- Workers register with Headscale
- `tailscale ping` works between all nodes
- All 4 nodes visible in `headscale nodes list`

### 7. ⏳ Update Documentation
- Update research.testing.md with successful test results
- Update plan.md spike criteria checkboxes
- Commit fixes

## Key Files Modified This Session

- `tests/fixtures/headscale-private.age` - Regenerated with hex format
- `tests/fixtures/headscale-noise.age` - Regenerated with hex format
- `tests/fixtures/headscale-derp.age` - Regenerated with hex format

## Key Files for Reference

- `tests/fixtures/test-age-key.txt` - Age identity for decryption
- `tests/fixtures/secrets.nix` - Agenix secret definitions
- `tests/microvm/cluster-primer.nix` - MicroVM config
- `modules/cluster/primer/headscale.nix` - Headscale K8s deployment
- `specs/006-clusters/plan.md` - Test validation log
- `specs/006-clusters/research.testing.md` - Testing documentation

## Commands to Resume

```bash
# Navigate to tests directory
cd /home/ncrmro/code/ncrmro/keystone/worktree/cluster-primer/tests

# Build microVM with fixed keys
nix build .#nixosConfigurations.cluster-primer.config.microvm.declaredRunner -o result-primer

# Run microVM
./result-primer/bin/microvm-run &

# SSH in (after boot)
ssh -i fixtures/test-ssh-key -p 22223 root@localhost

# Check Headscale status
kubectl get pods -n headscale-system
kubectl logs -n headscale-system deploy/headscale
```

## Success Criteria (from plan.md)

- [x] Primer boots via MicroVM with k3s running
- [ ] Headscale pod is healthy ← **Next to validate**
- [ ] Workers register via pre-auth key
- [ ] All 4 nodes can `tailscale ping` each other
- [x] Cluster is reachable from host via port-forwarding
