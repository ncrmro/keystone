---
repo: ncrmro/keystone
branch: feat/007-agent-ssh
agent: claude
priority: 6
status: ready
created: 2026-03-01
---

# SSH Key Management [SPEC-007 Task 8, FR-007]

## Description

Generate ed25519 SSH keypair per agent. Store private key + passphrase in agenix (declared by keystone module). Create `ssh-agent` systemd user service that auto-unlocks the key. Configure git to use SSH key for commit signing.

The keystone module declares:
- `age.secrets."agent-{name}-ssh-key"` (owner: agent-{name}, mode 0400)
- `age.secrets."agent-{name}-ssh-passphrase"` (owner: agent-{name}, mode 0400)

Tech stack: NixOS modules (Nix), openssh, ssh-agent, git, agenix. See `specs/007-os-agents/spec.md` FR-007 and FR-008.

Working branch: `spec/007-os-agents` (existing).

## Acceptance Criteria

- [x] `age.secrets."agent-researcher-ssh-key"` declared with owner `agent-researcher`, mode 0400
- [x] `age.secrets."agent-researcher-ssh-passphrase"` declared with owner `agent-researcher`, mode 0400
- [x] `ssh-agent` systemd user service auto-starts and unlocks key using agenix passphrase
- [x] Git configured with `gpg.format = ssh` and `user.signingkey` pointing to agent's key
- [x] Agent's public key in its own `~/.ssh/authorized_keys`
- [ ] VM test assertion: `systemctl --user -M agent-researcher@ is-active ssh-agent.service` succeeds
