# Fleet Survey

**Date**: Monday, March 23, 2026
**nixos-config path**: `/home/ncrmro/nixos-config`
**keystone path**: `/home/ncrmro/code/ncrmro/keystone`

## Keystone Revision Gap

- **Locked in flake.lock**: `77eec4918edf3b619b53038ff7903bd845d0137b` (2026-03-23)
- **Latest on main**: `4d64854605c8d900bff294591addec37afc5e588` (2026-03-23)
- **Commits behind**: 3 (Full log below)

### Changelog (oldest → newest)

| Hash | Message | Modules Touched |
|------|---------|-----------------|
| `2928716` | chore(deepwork): add next-step suggestions to press_release and milestone workflows | .deepwork/jobs/ |
| `f689f35` | docs: add comparison link to README hero section | README.md |
| `4d64854` | refactor(ks): dynamic repo discovery from repos.nix (REQ-018) | packages/ks/ks.sh |

## nixos-config Status

- **Branch**: master
- **Clean**: no — modified submodule `.submodules/keystone`
- **Recent commits**:
  ```
  9a06b2e feat(repos): add repos.nix registry and wire into keystone.repos
  bfefbbb chore: relock keystone + agenix-secrets
  9eaeedc chore(deps): update keystone submodule
  1ae6563 chore: relock keystone + agenix-secrets
  72884cc chore: relock keystone + agenix-secrets
  ```

## Preliminary Health (Current Host)

- **Hostname**: ncrmro-workstation
- **ks doctor summary**: PASS
- **Issues found**: None

## Host Reachability

| Host | Role | SSH Target | Reachable | Generation | Notes |
|------|------|------------|-----------|------------|-------|
| ncrmro-workstation | client | ncrmro-workstation.mercury | yes | 482 | current host |
| ocean | server | ocean.mercury | yes | 366 | attic, grafana |
| mercury | server | 216.128.136.32 | yes | 49 | VPS |
| maia | server | maia.mercury | yes | 40 | — |
| build-vm-desktop | client | null | no | — | offline |
| catalystPrimary | server | 144.202.67.5 | no | — | unreachable (timed out) |

## Agenix Secrets
- **Status**: clean
- **Up to date**: yes
