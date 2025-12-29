# Plan: Test Agenix Secret Management Flow with MicroVM

## Goal

Validate the complete agenix secrets flow for cluster-primer:
**agenix decryption → K8s Secret creation → Headscale pod mounting pre-provisioned keys**

## Current Status: IN PROGRESS (Build Works, VM Testing Incomplete)

### Completed ✅

1. **Test Fixtures Created** (`tests/fixtures/`)
   - `test-age-key.txt` - Age private key for VM decryption
   - `secrets.nix` - Agenix secret definitions
   - `headscale-private.age`, `headscale-noise.age`, `headscale-derp.age` - Encrypted keys
   - Public key: `age1u3f3r3h7m4rrl5dw97ee65fde38tfq0xk9ljdh5strf3z6a0js7q9g8hkj`

2. **tests/flake.nix Updated**
   - Added agenix input
   - Added agenix.nixosModules.default to cluster-primer configuration

3. **tests/microvm/cluster-primer.nix Updated**
   - Added `age.identityPaths = ["/etc/age/test-key.txt"]`
   - Added `age.secrets` for headscale-private, headscale-noise, headscale-derp
   - Added `environment.etc."age/test-key.txt"` to provision test key
   - Enabled `headscaleDeployment.useAgenixSecrets = true`

4. **modules/cluster/primer/headscale.nix Updated**
   - Added `useAgenixSecrets` option (default: false)
   - Added `headscale-secrets` systemd service that creates K8s Secret from `/run/agenix/`
   - Modified deployment to mount K8s Secret with subPath for individual key files
   - Added proper service ordering (headscale-secrets before headscale-deploy)

5. **Build Succeeds**
   - `nix build .#nixosConfigurations.cluster-primer.config.microvm.declaredRunner` works
   - `/nix/store/.../etc/age/test-key.txt` exists in the built output

### Issue Found 🔍

The microVM boots but `/etc/age/` and `/run/agenix/` are empty. The Nix evaluation shows correct configuration, and the build output contains the files, but the running VM doesn't have them.

**Likely cause**: The running VM was using a cached/stale system image. Need to:
1. Kill all QEMU processes
2. Delete `rancher.img` (persistent volume)
3. Rebuild and restart

### Next Steps

1. **Clean restart the microVM**
   ```bash
   cd /home/ncrmro/code/ncrmro/keystone/worktree/cluster-primer/tests
   pkill -9 -f qemu-system
   rm -f rancher.img result
   nix build .#nixosConfigurations.cluster-primer.config.microvm.declaredRunner
   ./result/bin/microvm-run
   ```

2. **Verify agenix decryption** (SSH into VM on port 22223)
   ```bash
   ls -la /etc/age/test-key.txt          # Should exist
   ls -la /run/agenix/                   # Should have headscale-* files
   systemctl status agenix.service       # Should be active
   ```

3. **Verify K8s Secret creation**
   ```bash
   systemctl status headscale-secrets.service
   kubectl get secret -n headscale-system headscale-keys -o yaml
   ```

4. **Verify Headscale pod mounts**
   ```bash
   kubectl exec -n headscale-system deploy/headscale -- ls -la /var/lib/headscale/
   kubectl exec -n headscale-system deploy/headscale -- cat /var/lib/headscale/private.key
   ```

5. **Commit changes** once all tests pass

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Test Flow: agenix → K8s Secret → Headscale Pod              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  tests/fixtures/                                            │
│  ├── test-age-key.txt     ─────┐                           │
│  ├── secrets.nix               │ age.identityPaths         │
│  ├── headscale-private.age ◄───┴─ agenix decrypts          │
│  ├── headscale-noise.age                                    │
│  └── headscale-derp.age                                     │
│           │                                                 │
│           ▼                                                 │
│  /run/agenix/headscale-*     (decrypted at boot)           │
│           │                                                 │
│           ▼                                                 │
│  kubectl create secret      (headscale-secrets.service)    │
│           │                                                 │
│           ▼                                                 │
│  K8s Secret: headscale-keys                                │
│           │                                                 │
│           ▼                                                 │
│  Headscale Pod volumeMount: /var/lib/headscale/            │
└─────────────────────────────────────────────────────────────┘
```

## Files Modified

| File | Status | Changes |
|------|--------|---------|
| `tests/fixtures/test-age-key.txt` | ✅ Created | Age keypair for test VM |
| `tests/fixtures/secrets.nix` | ✅ Created | Agenix secret definitions |
| `tests/fixtures/headscale-*.age` | ✅ Created | Encrypted Headscale keys |
| `tests/flake.nix` | ✅ Modified | Added agenix input |
| `tests/microvm/cluster-primer.nix` | ✅ Modified | Added age.secrets config |
| `modules/cluster/primer/headscale.nix` | ✅ Modified | Added K8s Secret creation |

## Success Criteria

1. ✓ Build succeeds
2. ⏳ `/run/agenix/headscale-*` files exist after boot
3. ⏳ K8s Secret `headscale-keys` created in `headscale-system` namespace
4. ⏳ Headscale pod mounts and reads keys successfully
5. ⏳ Headscale starts without auto-generating keys

## Port Conflicts Note

Port 18080 conflicts with something on the host. If needed, change the Headscale HTTP forward port in `tests/microvm/cluster-primer.nix`.
