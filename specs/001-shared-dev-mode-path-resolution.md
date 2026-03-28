# Spec: Shared dev-mode path resolution

## Stories Covered

- US-001: Link supported repo-backed assets from local checkouts
- US-002: Apply linked changes without another rebuild for supported assets
- US-003: Preserve the locked build and deploy path
- US-004: Use the same development-mode model for users and OS agents

## Affected Modules

- `modules/shared/repos.nix`
- `modules/shared/dev-script-link.nix`
- `modules/terminal/default.nix`
- `modules/os/users.nix`
- `modules/os/agents/home-manager.nix`

## Data Models

### Managed repo entry (`keystone.repos.<owner/repo>`)

| Field      | Type           | Required | Notes                            |
| ---------- | -------------- | -------- | -------------------------------- |
| key        | `owner/repo`   | yes      | Canonical repo identity          |
| url        | string         | yes      | Git remote URL                   |
| flakeInput | string or null | no       | Used to match dev-mode overrides |
| branch     | string         | no       | Defaults to `main`               |

### Supported asset family contract

| Field          | Type           | Required | Notes                                                                       |
| -------------- | -------------- | -------- | --------------------------------------------------------------------------- |
| family         | string         | yes      | Stable name for an asset family                                             |
| repoFlakeInput | string or null | no       | Repo lookup key when the asset lives in a managed repo                      |
| relativePath   | string         | yes      | Path inside the repo checkout                                               |
| lockedSource   | path/value     | yes      | Immutable source used when dev mode is off                                  |
| liveEditable   | bool           | yes      | Whether post-activation edits are expected to apply without another rebuild |

## Interface definitions

### Path resolution contract

1. Resolve the repo checkout from `keystone.repos` using `flakeInput` where available.
2. If `keystone.development = true` and the checkout exists, resolve supported assets from `~/.keystone/repos/{owner}/{repo}/{relativePath}`.
3. If `keystone.development = false` or no matching checkout exists, resolve the same assets from their immutable source.

## Behavioral Requirements

1. The system MUST expose a shared path-resolution pattern for supported repo-backed asset families instead of implementing per-family ad hoc repo lookups.
2. The shared resolver MUST derive checkout paths from `keystone.repos`, not from hardcoded per-user absolute paths.
3. The shared resolver MUST preserve the current locked-mode behavior when `keystone.development = false`.
4. Supported asset families MUST declare both their checkout-backed source and their immutable fallback.
5. Unsupported or generated asset families MUST keep their current behavior until they are explicitly added to the supported set.
6. Home Manager consumers SHOULD reuse the shared resolver or a thin wrapper around it rather than duplicating lookup logic.
7. The system MAY skip checkout-backed resolution for a supported family when the matching managed repo is not declared or does not exist locally, but it MUST fall back cleanly to the immutable source.
8. Human users and OS agents MUST inherit the same top-level development-mode and repo-registry inputs.
9. The resolver MUST only influence path selection. It MUST NOT modify, commit, or push managed repositories.

## Edge Cases

- A repo entry with `flakeInput = null` MUST NOT be treated as a checkout-backed source for asset families that require a flake input match.
- If multiple repo entries could match the same asset family, the resolver MUST apply a deterministic selection rule and document it.
- If a local checkout path exists but the referenced file is missing, activation MUST fail with a targeted error or fall back to the immutable source; it MUST NOT silently create a broken symlink.
- If an asset family spans multiple repos, each path MUST be resolved independently so one missing checkout does not break unrelated families.

## Cross-spec dependencies

- `specs/002-repo-backed-terminal-assets.md`
- `specs/003-theme-asset-pipeline-and-runtime-reload.md`
- `specs/005-agent-development-parity.md`
