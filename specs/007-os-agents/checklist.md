# SPEC-007: OS Agents — Consistency Checklist

**Date**: 2026-03-01
**Spec**: specs/007-os-agents/
**Amendment**: Chrome DevTools MCP stdio transport + human access

## Summary

| Check | Result | Details |
|-------|--------|---------|
| Spec → Plan | PASS | All 15 FRs and 4 NFRs mapped to plan components |
| Plan → Tasks | PASS | All files and 7 phases covered |
| Spec → Tasks | PASS | All 15 FRs referenced by tasks |
| RFC 2119 Compliance | PASS | All FRs use uppercase RFC 2119 keywords |
| Unresolved Markers | WARN | Open Questions 4-5 unresolved (future scope); 1-3 resolved |
| Over-Engineering | PASS | All components trace to requirements |
| Dependency Integrity | PASS | No circular refs; [P] markers correct; graph/body reconciled |

**Overall**: PASS (with advisory warnings, unchanged from prior checklist)

## Amendment-Specific Checks

| Check | Result | Details |
|-------|--------|---------|
| FR-003 spec ↔ plan consistency | PASS | Both specify chrome-devtools-mcp, stdio transport, --browserUrl, human access |
| FR-003 spec ↔ tasks consistency | PASS | Task 4 packages Nix derivation, Task 10 generates .mcp.json entry |
| FR-015 spec ↔ plan consistency | PASS | Both specify Nix derivation, stdio (no systemd service), /etc/keystone/agent-mcp/ human config |
| FR-015 spec ↔ tasks consistency | PASS | Task 10 acceptance criteria match FR-015 requirements |
| No stale systemd MCP references | PASS | Removed from architecture diagram, dependency graph, technology stack |
| Chrome DevTools MCP transport consistency | PASS | All three files consistently describe stdio transport (not systemd service) |

## Detailed Results

### Spec → Plan Traceability

| FR ID | Plan Component | Status |
|-------|---------------|--------|
| FR-001 | `agents.nix`, Phase 1 | PASS |
| FR-002 | `agents.nix` (labwc + wayvnc), Phase 2 | PASS |
| FR-003 | `agents/chrome.nix` + overlay derivation, Phase 2 | PASS |
| FR-004 | `agents/mail.nix`, Phase 3 | PASS |
| FR-005 | `agents/bitwarden.nix`, Phase 3 | PASS |
| FR-006 | `agents/tailscale.nix`, Phase 3 | PASS |
| FR-007 | `agents/ssh.nix`, Phase 3 | PASS |
| FR-008 | `agents/secrets.nix`, Phase 1 | PASS |
| FR-009 | `agents/agent-space.nix`, Phase 4 | PASS |
| FR-010 | `agents/task-loop.nix`, Phase 5 | PASS |
| FR-011 | `agents/audit.nix`, Phase 5 | PASS |
| FR-012 | `tests/module/agent-isolation.nix`, Phases 1/2/7 | PASS |
| FR-013 | `agents/coding-agent.nix`, Phase 6 | PASS |
| FR-014 | `agents/incidents.nix`, Phase 6 | PASS |
| FR-015 | `agents/mcp.nix` (stdio .mcp.json + /etc/keystone/agent-mcp/), Phase 4 | PASS |

| NFR ID | Plan Coverage | Status |
|--------|--------------|--------|
| NFR-001 (Observability) | `agent-desktops.target` in desktop, audit.nix | PASS |
| NFR-002 (Isolation) | Security Considerations table, Phase 7 tests | PASS |
| NFR-003 (Declarative) | Core design throughout; mirrors users.nix pattern | PASS |
| NFR-004 (Resource Limits) | Config example has `resources = {}`, tested in Phase 7 cgroup assertions | WARN |

**NFR-004 Note**: Same as prior checklist — the `resources` option (cpuQuota, memoryMax) appears in the config example and Phase 7 tests, but no plan file is explicitly responsible for the systemd resource control wiring.

### Plan → Tasks Traceability

| Plan File | Task(s) | Status |
|-----------|---------|--------|
| `modules/os/agents.nix` | Tasks 1, 3 | PASS |
| `modules/os/agents/chrome.nix` | Task 4 | PASS |
| Keystone overlay derivation (chrome-devtools-mcp) | Task 4 | PASS |
| `modules/os/agents/mail.nix` | Task 5 | PASS |
| `modules/os/agents/bitwarden.nix` | Task 6 | PASS |
| `modules/os/agents/tailscale.nix` | Task 7 | PASS |
| `modules/os/agents/ssh.nix` | Task 8 | PASS |
| `modules/os/agents/agent-space.nix` | Task 9 | PASS |
| `modules/os/agents/scripts/scaffold-agent-space.sh` | Task 9 | PASS |
| `modules/os/agents/mcp.nix` | Task 10 | PASS |
| `/etc/keystone/agent-mcp/{name}.json` (human config) | Task 10 | PASS |
| `modules/os/agents/task-loop.nix` | Task 11 | PASS |
| `modules/os/agents/scripts/task-loop.sh` | Task 11 | PASS |
| `modules/os/agents/audit.nix` | Task 12 | PASS |
| `modules/os/agents/scripts/audit-logger.sh` | Task 12 | PASS |
| `modules/os/agents/coding-agent.nix` | Task 13 | PASS |
| `modules/os/agents/scripts/coding-agent.sh` | Task 13 | PASS |
| `modules/os/agents/incidents.nix` | Task 14 | PASS |
| `tests/module/agent-isolation.nix` | Tasks 2, 15 | PASS |
| `modules/os/default.nix` (modified) | Task 1 | PASS |
| `flake.nix` (modified) | Task 16 | PASS |

### Spec → Tasks Traceability

| FR | Task(s) | Status |
|----|---------|--------|
| FR-001 | Task 1 | PASS |
| FR-002 | Task 3 | PASS |
| FR-003 | Task 4 | PASS |
| FR-004 | Task 5 | PASS |
| FR-005 | Task 6 | PASS |
| FR-006 | Task 7 | PASS |
| FR-007 | Task 8 | PASS |
| FR-008 | Task 1 | PASS |
| FR-009 | Task 9 | PASS |
| FR-010 | Task 11 | PASS |
| FR-011 | Task 12 | PASS |
| FR-012 | Tasks 2, 15, 16 | PASS |
| FR-013 | Task 13 | PASS |
| FR-014 | Task 14 | PASS |
| FR-015 | Task 10 | PASS |

### RFC 2119 Compliance

All 15 FRs use RFC 2119 keywords (MUST, MUST NOT, SHALL, SHOULD, MAY) in uppercase. The amended FR-003 and FR-015 maintain compliance — new requirements use MUST and SHOULD appropriately. PASS.

### Unresolved Markers

| File | Location | Marker | Context |
|------|----------|--------|---------|
| requirements.md | Open Questions §1-3 | Open Question | Resolved in plan.md (labwc, wayvnc, Chrome deferred) |
| requirements.md | Open Questions §4 | Open Question | Agent-to-agent communication — future scope |
| requirements.md | Open Questions §5 | Open Question | Lifecycle CLI — future scope |

No `[TBD]`, `[TODO]`, `???`, or empty sections found. No stale references to "systemd MCP service" remain in any file.

### Over-Engineering Check

| Item | Traces To | Status |
|------|-----------|--------|
| chrome-devtools-mcp Nix derivation | FR-003, FR-015 | PASS |
| /etc/keystone/agent-mcp/ human config | FR-003 (human access), FR-015 (discoverable config) | PASS |
| All other plan components | FR-001 through FR-015 | PASS |

No gold-plating detected. The human-accessible config fragments are explicitly required by the spec.

### Dependency Integrity

- **Circular references**: None
- **Parallel marker conflicts**: None — all `[P]` tasks modify unique files
- **Checkpoint coverage**: Complete — all 7 phases have checkpoints with verifiable criteria
- **Task 10 dependency update**: Changed from Task 3 to Task 4 (correct — needs chrome-devtools-mcp derivation from Task 4)
- **Shared test file**: Parallel tasks extend `tests/module/agent-isolation.nix` via validation steps (additive, not conflicting)

## Recommendations

1. **NFR-004**: Same as prior — add resource limit wiring to Task 1 acceptance criteria.
2. **Open Questions 1-3**: Optionally close in requirements.md by documenting decisions inline. Not blocking.
3. **Open Questions 4-5**: Leave as-is — future scope.
4. **Overlay derivation path**: Task 4 mentions "Keystone overlay derivation" without specifying the exact file path. Implementer should decide placement (e.g., `overlays/chrome-devtools-mcp/default.nix`). Minor — does not block implementation.
