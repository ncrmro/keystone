# Spec: Repo-backed terminal assets

## Stories Covered

- US-001: Link supported repo-backed assets from local checkouts
- US-002: Apply linked changes without another rebuild for supported assets
- US-004: Use the same development-mode model for users and OS agents

## Affected Modules

- `modules/shared/dev-script-link.nix`
- `modules/desktop/home/scripts/default.nix`
- `modules/terminal/ai-extensions.nix`
- `modules/terminal/deepwork.nix`
- `modules/terminal/shell.nix`
- `modules/os/agents/agentctl.nix`

## Data Models

### Terminal asset family matrix

| Family               | Current consumer                   | Mutable after activation | Primary source                    |
| -------------------- | ---------------------------------- | ------------------------ | --------------------------------- |
| Shell entrypoints    | `~/.local/bin/*`                   | yes                      | repo checkout or package fallback |
| AI command templates | tool config directories            | yes                      | repo checkout or module source    |
| DeepWork jobs        | `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` | yes                      | repo checkout or packaged jobs    |
| Zellij layouts       | `~/.config/zellij/layouts/*.kdl`   | yes                      | repo checkout or module source    |
| Agent helper script  | `~/.local/bin/agentctl`            | yes after activation     | repo checkout or packaged helper  |

## Interface definitions

### Shell entrypoint contract

| Field            | Type   | Required | Notes                                   |
| ---------------- | ------ | -------- | --------------------------------------- |
| targetPath       | string | yes      | User-visible path under `~/.local/bin/` |
| relativeRepoPath | string | yes      | Checkout path to the backing script     |
| executable       | bool   | yes      | Backing file must remain executable     |

### Zellij layout contract

| Field      | Type   | Required | Notes                                        |
| ---------- | ------ | -------- | -------------------------------------------- |
| name       | string | yes      | Layout name such as `dev`, `ops`, or `write` |
| targetPath | string | yes      | `~/.config/zellij/layouts/{name}.kdl`        |
| sourcePath | string | yes      | Checkout-backed path or immutable fallback   |

## Behavioral Requirements

1. Supported terminal shell entrypoints backed by checked-in scripts MUST resolve from the local checkout in dev mode and from immutable packages otherwise.
2. AI command templates and DeepWork job folders MUST continue their current dev-mode checkout behavior and SHOULD be normalized onto the shared asset-family contract from `specs/001-shared-dev-mode-path-resolution.md`.
3. Zellij layouts under `modules/terminal/layouts/` MUST become supported repo-backed assets in dev mode.
4. The initial activation step MUST create the user-visible links for supported terminal assets.
5. After activation, edits to directly linked terminal assets MUST take effect without another rebuild.
6. Terminal asset support MUST NOT require users to edit generated files under XDG target directories directly.
7. When dev mode is off, terminal assets MUST remain reproducible and MUST resolve from immutable sources.
8. Agent-facing terminal assets, including `agentctl` where relevant, MUST follow the same resolution rules as human-facing terminal assets.
9. Terminal asset families MAY opt out of live-edit behavior only when their target tool requires generated output; any such exception MUST be documented.

## Edge Cases

- If a backing script loses its executable bit in the checkout, activation MUST fail with a clear error or restore the packaged fallback.
- If a tool-specific config directory does not yet exist, activation MUST create it before linking supported assets.
- If a user disables a terminal submodule that owns an asset family, the system MUST remove or stop managing that target path cleanly.
- If a supported asset path collides with a user-created regular file, activation MUST surface the conflict instead of silently overwriting it.

## Cross-spec dependencies

- `specs/001-shared-dev-mode-path-resolution.md`
- `specs/005-agent-development-parity.md`
