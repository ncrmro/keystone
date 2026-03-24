# Update Plan

**Date**: Monday, March 23, 2026
**Keystone gap**: `77eec49` → `4d64854` (3 commits)
**Pre-existing issues**: 0

## Change Triage

### Verify Only

| # | Commit | Summary | Affected Hosts | Post-Deploy Check |
|---|--------|---------|----------------|-------------------|
| 1 | `2928716` | chore(deepwork): add next-step suggestions | none (workflow logic) | — |
| 2 | `f689f35` | docs: add comparison link to README | none (docs) | — |
| 3 | `4d64854` | refactor(ks): dynamic repo discovery (REQ-018) | all hosts | `ks build` identifies overrides |

### Ad-Hoc Fixes (before deploy)
None needed.

### Needs Issue
None.

## Deployment Plan

### Order
1. **ncrmro-workstation** (current host) — `ks update --lock`
2. **ocean** — remote deploy via Tailscale
3. **mercury** — remote deploy via VPS IP
4. **maia** — remote deploy via Tailscale
5. [deferred: build-vm-desktop — offline]
6. [deferred: catalystPrimary — unreachable]

### Flags
- `--boot` required: no
- Expected build time: 1-2 minutes (minimal Nix changes)

## Post-Deployment Verification Checklist

- [ ] `ks doctor` on current host shows PASS
- [ ] `ks build` correctly identifies local overrides via `repos.nix` registry
- [ ] Remote hosts: `ssh root@ocean systemctl --failed` shows no failures
- [ ] Agent health: `agentctl drago status` nominal on workstation

## Risk Assessment

- **Overall risk**: low
- **Rollback plan**: Previous generation available via `nixos-rebuild switch --rollback`
- **Blockers**: none
