# Spec: Agent development parity

## Stories Covered
- US-004: Use the same development-mode model for users and OS agents

## Affected Modules
- `modules/terminal/default.nix`
- `modules/os/users.nix`
- `modules/os/agents/home-manager.nix`
- `modules/os/agents/agentctl.nix`
- `tests/module/agent-evaluation.nix`
- `docs/agents/os-agents.md`
- `docs/agents/os-agents.agent-space.md`

## Data Models

### Principal parity contract
| Principal | Home root | Managed repo root | Dev-mode source |
|-----------|-----------|-------------------|-----------------|
| Human user | `/home/{user}` | `~/.keystone/repos` | inherited from `keystone.development` |
| OS agent | `/home/agent-{name}` | `~/.keystone/repos` under the agent home | inherited from `keystone.development` |

### Exception record
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| assetFamily | string | yes | Family that diverges from parity |
| reason | string | yes | Tooling limitation or non-applicability |
| scope | string | yes | Human-only, agent-only, or host-specific |
| fallbackBehavior | string | yes | What happens instead |

## Interface definitions

### Shared inheritance contract
- NixOS-level `keystone.development` and `keystone.repos` are the source of truth.
- Home Manager modules for both human users and agents consume those values through the same bridge.
- Asset-family modules decide relevance per principal, but MUST use the same resolution rules when relevant.

## Behavioral Requirements

1. Human users and OS agents MUST inherit `keystone.development` and `keystone.repos` from the same top-level source of truth.
2. When an asset family is relevant to both humans and agents, the family MUST use the same checkout-backed versus immutable resolution rules for both principals.
3. Agent-specific helper scripts such as `agentctl` MUST continue to support checkout-backed linking where that capability already exists.
4. Any asset family that is intentionally unsupported for agents MUST document the reason as an explicit exception record.
5. Agent parity tests MUST cover at least one development-mode path-resolution case beyond the existing DeepWork jobs check when new supported asset families are added for agents.
6. The system SHOULD avoid adding agent-only enable flags for development mode when shared inheritance is sufficient.
7. Documentation MUST explain any cases where an agent cannot consume a symlinked payload directly.
8. Agent parity requirements MAY be a no-op for desktop-only asset families that agents do not use, but the non-applicability MUST be documented.

## Edge Cases

- If an agent home does not enable the terminal module, terminal asset-family links MUST NOT be created for that agent.
- If an agent-specific service requires a packaged binary rather than a checkout-backed script, the exception MUST be documented and tested.
- If human and agent homes resolve the same repo key to different filesystem roots, the logical repo identity MUST still be consistent.
- If a future asset family is relevant only on one class of principal, the docs MUST mark that scope clearly to avoid false parity expectations.

## Cross-spec dependencies
- `specs/001-shared-dev-mode-path-resolution.md`
- `specs/002-repo-backed-terminal-assets.md`
- `specs/004-lock-and-deploy-safety.md`
