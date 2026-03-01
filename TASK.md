---
repo: ncrmro/keystone
branch: feat/007-chromium-browser
agent: claude
priority: 1
status: ready
created: 2026-03-01
---

# Chromium Browser Service [SPEC-007 Task 4a, FR-003]

## Description

Add Chromium browser as a systemd system service for OS agents. Each agent with `chrome.enable = true` gets a Chromium instance that launches on its labwc desktop with remote debugging enabled.

The debug port must be auto-assigned from base 9222 to avoid conflicts across agents (agent index 0 → 9222, index 1 → 9223, etc.). `chrome.debugPort = null` triggers auto-assignment; an explicit integer overrides.

Tech stack: NixOS modules (Nix), systemd services with `User=` directive (not user services), labwc compositor (already implemented in `modules/os/agents.nix`). See `specs/007-os-agents/` for full spec and plan.

Working branch: `spec/007-os-agents` (existing). The agents module is consolidated in `modules/os/agents.nix`.

## Acceptance Criteria

- [x] `keystone.os.agents.researcher.chrome.enable = true` activates Chromium service
- [x] Chromium starts with `--remote-debugging-port={debugPort}` on the agent's desktop
- [x] `chrome.debugPort = null` auto-assigns from base 9222 (per agent index)
- [x] Explicit `chrome.debugPort = 9300` overrides auto-assignment
- [x] Chromium profile persists at `/home/agent-{name}/.config/chromium-agent/`
- [x] Chromium systemd service starts `After=labwc-agent-{name}.service`
- [x] Remote debugging port is accessible from localhost: `curl -s http://localhost:{port}/json/version`
- [x] VM test assertion added: Chromium process active, debug port responding
- [x] Multiple agents get non-conflicting debug ports
