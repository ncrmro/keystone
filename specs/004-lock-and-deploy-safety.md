# Spec: Lock and deploy safety for development mode

## Stories Covered

- US-003: Preserve the locked build and deploy path
- US-005: Document how to use and publish development-mode changes

## Affected Modules

- `packages/ks/ks.sh`
- `modules/shared/repos.nix`
- `specs/REQ-018-repo-management/requirements.md`
- `specs/REQ-019-ks-cli/requirements.md`
- `conventions/process.keystone-development-mode.md`
- `CLAUDE.md`
- `README.md`
- `docs/terminal/terminal.md`

## Data Models

### Command mode contract

| Command           | Mode   | Expected source behavior              | Publish gate           |
| ----------------- | ------ | ------------------------------------- | ---------------------- |
| `ks build`        | dev    | Local overrides allowed               | none                   |
| `ks update --dev` | dev    | Local overrides allowed               | none                   |
| `ks build --lock` | locked | Immutable inputs and lock updates     | clean and pushed repos |
| `ks update`       | locked | Immutable inputs and deployable build | clean and pushed repos |

### Release guidance contract

| Topic            | Required output                                                |
| ---------------- | -------------------------------------------------------------- |
| Enablement       | How to set `keystone.development = true` and register repos    |
| Live-edit matrix | Which assets are live-editable after activation                |
| Lock path        | When to commit, push, and run `ks build --lock` or `ks update` |
| Exceptions       | Which assets still require regeneration or rebuild             |

## Behavioral Requirements

1. The locked workflow MUST continue to use immutable sources for supported asset families when `keystone.development = false`.
2. `ks build --lock` and `ks update` MUST retain the existing repo cleanliness, push, and lock gating semantics.
3. Development-mode path resolution MUST NOT bypass or weaken managed-repo release checks.
4. The implementation MUST ensure that checkout-backed asset links do not leak into locked builds.
5. User guidance MUST document the difference between initial activation in dev mode and the publish path for locked builds.
6. User guidance MUST name the supported live-editable asset families and MUST call out any exceptions that still require regeneration or rebuild.
7. The release workflow SHOULD keep using the existing commands rather than introducing a separate “promote dev changes” migration step.
8. `ks doctor` and related guidance MAY surface whether managed repos are present and clean, but they MUST NOT be required for local iteration to function.
9. The documentation set MUST remain internally consistent across specs, conventions, and user-facing docs.

## Edge Cases

- If a user enables development mode without a local checkout for a supported repo, the system MUST fall back to immutable sources and SHOULD explain why live editing is unavailable.
- If a repo is dirty in development mode, local iteration MUST still work, but locked commands MUST continue to reject release operations until the repo is clean and pushed.
- If documentation cannot confidently classify an asset family as live-editable, it MUST describe the family as unsupported until implementation proves otherwise.
- If a supported asset requires an activation step before live editing begins, the docs MUST state that prerequisite explicitly.

## Cross-spec dependencies

- `specs/001-shared-dev-mode-path-resolution.md`
- `specs/003-theme-asset-pipeline-and-runtime-reload.md`
- `specs/005-agent-development-parity.md`
