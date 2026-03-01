---
repo: ncrmro/keystone
branch: feat/007-agent-bitwarden
agent: claude
priority: 4
status: ready
created: 2026-03-01
---

# Bitwarden Account [SPEC-007 Task 6, FR-005]

## Description

Configure Vaultwarden integration for each agent with `bitwarden.enable = true`. Store password in agenix. Install and pre-configure `bw` CLI. Create a dedicated Bitwarden collection per agent.

The keystone module declares `age.secrets."agent-{name}-bitwarden-password"` with owner `agent-{name}`, mode 0400. Consumer provides `.age` files.

Tech stack: NixOS modules (Nix), Vaultwarden, bitwarden-cli (`bw`), agenix. See `specs/007-os-agents/spec.md` FR-005 and FR-008.

Working branch: `spec/007-os-agents` (existing).

## Acceptance Criteria

- [x] `keystone.os.agents.researcher.bitwarden.enable = true` configures Vaultwarden access
- [x] `age.secrets."agent-researcher-bitwarden-password"` declared with owner `agent-researcher`, mode 0400
- [x] `bw` CLI available in agent's PATH and pre-configured with server URL
- [x] Collection scoped to `agent-researcher`
- [ ] VM test assertion: `su - agent-researcher -c "which bw"` succeeds
