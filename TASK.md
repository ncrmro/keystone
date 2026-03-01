---
repo: ncrmro/keystone
branch: feat/007-agent-email
agent: claude
priority: 3
status: ready
created: 2026-03-01
---

# Email via Stalwart [SPEC-007 Task 5, FR-004]

## Description

Configure a Stalwart mail account for each agent with `mail.enable = true`. Generate IMAP/SMTP credentials stored in agenix. Configure himalaya CLI in agent's environment for programmatic email access.

The keystone module declares `age.secrets."agent-{name}-mail-password"` with owner `agent-{name}`, mode 0400. The consumer (nixos-config) provides the encrypted `.age` files.

Tech stack: NixOS modules (Nix), Stalwart mail server, himalaya CLI, agenix. See `specs/007-os-agents/spec.md` FR-004 and FR-008.

Working branch: `spec/007-os-agents` (existing).

## Acceptance Criteria

- [x] `keystone.os.agents.researcher.mail.enable = true` declares Stalwart account config
- [x] `age.secrets."agent-researcher-mail-password"` declared with owner `agent-researcher`, mode 0400
- [x] himalaya config generated at `~/.config/himalaya/config.toml` referencing agenix secret path
- [x] Mail account address follows `agent-{name}@{domain}` pattern
- [x] CalDAV/CardDAV access provisioned when mail is enabled
- [x] VM test assertion: himalaya config file exists at expected path
