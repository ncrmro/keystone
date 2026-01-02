# Keystone Agent Sandbox - Current Progress

## Goal

Fix the `keystone-agent` sandbox so that:
1. `--fresh` actually kills and restarts the VM (no zombie VMs)
2. Workspace passthrough works (files sync between host and guest)
3. Agent can write to `/workspace` without permission issues

## Completed Fixes

### Fix 1: Cache-Busting Timestamp ✅
**Problem**: Nix caches builds based on derivation hash. Identical `flake.nix` = same hash = cached result.

**Solution**: Added unique build timestamp to generated flake:
```python
build_id = int(time.time())
# In flake.nix:
environment.etc."sandbox-build-id".text = "{build_id}";
```

**File**: `packages/keystone-agent/agent.py` - `generate_sandbox_flake()` function

### Fix 2: Process Group Killing ✅
**Problem**: Registry stored wrapper PID, not QEMU PID. Killing wrapper didn't kill QEMU.

**Solution**:
- Store PGID in registry alongside PID
- Use `os.killpg()` to kill entire process group
- Added `_verify_port_free()` to confirm port is actually free
- Added `_kill_by_port()` as fallback using lsof

**File**: `packages/keystone-agent/agent.py` - `stop_microvm()`, `start_microvm()`, `_verify_port_free()`, `_kill_by_port()`

### Fix 3: 9p Share Configuration ✅
**Problem**: VirtioFS requires separate virtiofsd daemon. Files showed as root-owned in guest.

**Solution**:
- Use 9p (default) instead of virtiofs
- Use `securityModel = "mapped"` - stores guest UID/GID as xattrs on host
- Files created by sandbox user appear as sandbox-owned in guest
- Direct writes work without sudo
- Removed `access=any` mount option (not needed with mapped mode)

**File**: `packages/keystone-agent/agent.py` - flake generation in `generate_sandbox_flake()`

### Fix 4: Delete flake.lock Before Build ✅
**Problem**: Lock file pins input versions, contributing to cache hits.

**Solution**: Delete `flake.lock` before each build in `build_microvm()`

**File**: `packages/keystone-agent/agent.py` - `build_microvm()` function

### Fix 5: SSH Public Key Authentication ✅
**Problem**: User was prompted for password on SSH login.

**Solution**: Added `get_ssh_public_key()` function that reads user's SSH public key and injects it into the sandbox's authorized_keys.

**File**: `packages/keystone-agent/agent.py` - `get_ssh_public_key()` function

### Fix 6: Home Directory Creation ✅
**Problem**: `/home` is tmpfs, so `/home/sandbox` doesn't exist after boot.

**Solution**: Added systemd service `create-sandbox-home` that creates the directory after boot.

**File**: `packages/keystone-agent/agent.py` - flake generation

### Fix 7: Passwordless Sudo ✅
**Problem**: Agent may need root access for some operations.

**Solution**: Added passwordless sudo for sandbox user (useful for system commands, not required for /workspace writes):
```nix
security.sudo.extraRules = [{
  users = [ "sandbox" ];
  commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
}];
```

**File**: `packages/keystone-agent/agent.py` - flake generation

## Current Status

**COMPLETED** - All fixes verified working!

Last verified (2026-01-02):
- Sandbox user CAN write to `/workspace` directly (no sudo needed)
- File creation, append, and touch all work
- Files created in guest appear as `sandbox:users` in guest
- Files appear on host owned by the QEMU process user (ncrmro)
- Guest UID/GID stored as xattrs on host files

## Known Limitations

- **Existing host files appear as root-owned in guest** (no xattrs)
- Files created by sandbox user work perfectly
- For existing files, use sudo or sync mechanism

## Key Files

| File | Purpose |
|------|---------|
| `packages/keystone-agent/agent.py` | Main agent implementation |
| `packages/keystone-agent/default.nix` | Nix package definition (includes lsof dep) |
| `specs/012-agent-sandbox/research.v2-workflow.md` | Bug documentation and security analysis |
| `~/.config/keystone/agent/sandboxes/default/` | Generated sandbox directory |

## Security Documentation

See `specs/012-agent-sandbox/research.v2-workflow.md` for:
- Threat model for agent sandboxes
- Why passwordless sudo is required (and why it's safe)
- Agent escape scenarios and mitigations
- Recommended usage patterns

## Commands Reference

```bash
# Build agent
nix build .#keystone-agent

# Start sandbox (fresh)
result/bin/keystone-agent start --fresh

# Start without attaching
result/bin/keystone-agent start --fresh --no-attach

# SSH into sandbox
ssh -p 2223 sandbox@localhost

# Stop sandbox
result/bin/keystone-agent stop

# List sandboxes
result/bin/keystone-agent list

# Kill zombie on port 2223
lsof -ti :2223 | xargs -r kill -9
```

---

# Previous Plan: Agenix Secret Management (Archived)

## Goal

Validate the complete agenix secrets flow for cluster-primer:
**agenix decryption → K8s Secret creation → Headscale pod mounting pre-provisioned keys**

## Status: IN PROGRESS (Build Works, VM Testing Incomplete)

### Completed ✅

1. **Test Fixtures Created** (`tests/fixtures/`)
   - `test-age-key.txt` - Age private key for VM decryption
   - `secrets.nix` - Agenix secret definitions
   - `headscale-private.age`, `headscale-noise.age`, `headscale-derp.age` - Encrypted keys

2. **tests/flake.nix Updated** - Added agenix input

3. **tests/microvm/cluster-primer.nix Updated** - Added age.secrets config

4. **modules/cluster/primer/headscale.nix Updated** - Added K8s Secret creation

5. **Build Succeeds**

### Issue Found 🔍

The microVM boots but `/etc/age/` and `/run/agenix/` are empty. Likely stale cache issue.

### Next Steps

1. Clean restart the microVM (kill QEMU, delete rancher.img, rebuild)
2. Verify agenix decryption
3. Verify K8s Secret creation
4. Verify Headscale pod mounts
