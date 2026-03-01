---
repo: ncrmro/keystone
branch: feat/007-per-agent-tailscale
agent: claude
priority: 5
status: ready
created: 2026-03-01
---

# Per-Agent Tailscale Instances [SPEC-007 Task 7, FR-006]

## Description

Configure per-agent `tailscaled` daemon instances. Each agent with `tailscale.enable = true` gets its own state directory, socket, TUN interface, and tailscale CLI wrapper. UID-based fwmark rules route agent traffic through their specific TUN.

Each instance:
- State: `/var/lib/tailscale/tailscaled-agent-{name}.state`
- Socket: `/run/tailscale/tailscaled-agent-{name}.socket`
- TUN: `tailscale-agent-{name}`
- Auth key: `/run/agenix/agent-{name}-tailscale-auth-key` (owner: root, mode 0400)

A `tailscale` CLI wrapper in the agent's PATH auto-specifies `--socket`. Fallback to host Tailscale via `tailscale0` when `tailscale.enable = false`.

Tech stack: NixOS modules (Nix), tailscale/tailscaled, nftables, agenix. See `specs/007-os-agents/spec.md` FR-006.

Working branch: `spec/007-os-agents` (existing).

## Acceptance Criteria

- [x] `tailscaled-agent-researcher.service` runs with unique state/socket/TUN
- [x] Agent appears as `agent-researcher` on the Headscale tailnet
- [x] `age.secrets."agent-researcher-tailscale-auth-key"` declared with owner root, mode 0400
- [x] nftables fwmark rule routes uid 4001 traffic through `tailscale-agent-researcher`
- [x] `tailscale` wrapper in agent's PATH auto-specifies `--socket`
- [x] `tailscale.enable = false` falls back to host Tailscale via `tailscale0`
- [ ] VM test assertion: `systemctl is-active tailscaled-agent-researcher.service` succeeds
- [ ] VM test assertion: fwmark rules present in nftables
