# SPEC-007: OS Agents — Consistency Checklist

**Date**: 2026-02-24
**Spec**: specs/007-os-agents/

## Summary

| Check | Result | Details |
|-------|--------|---------|
| Spec → Plan | WARN | NFR-004 resource limits not explicitly assigned to a plan file |
| Plan → Tasks | PASS | All 23 files and 7 phases covered |
| Spec → Tasks | PASS | All 15 FRs referenced by tasks |
| RFC 2119 Compliance | PASS | All FRs use uppercase RFC 2119 keywords |
| Unresolved Markers | WARN | Open Questions 4-5 unresolved; 1-3 resolved in plan but not formally closed |
| Over-Engineering | PASS | All components trace to requirements |
| Dependency Integrity | PASS | No circular refs; [P] markers correct; graph/body reconciled |

**Overall**: PASS (with advisory warnings)

## Detailed Results

### Spec → Plan Traceability

| FR ID | Plan Component | Status |
|-------|---------------|--------|
| FR-001 | `agents/users.nix`, Phase 1 | PASS |
| FR-002 | `agents/desktop.nix`, Phase 2 | PASS |
| FR-003 | `agents/chrome.nix`, Phase 2 | PASS |
| FR-004 | `agents/mail.nix`, Phase 3 | PASS |
| FR-005 | `agents/bitwarden.nix`, Phase 3 | PASS |
| FR-006 | `agents/tailscale.nix`, Phase 3 | PASS |
| FR-007 | `agents/ssh.nix`, Phase 3 | PASS |
| FR-008 | `agents/secrets.nix`, Phase 1 | PASS |
| FR-009 | `agents/agent-space.nix`, Phase 4 | PASS |
| FR-010 | `agents/task-loop.nix`, Phase 5 | PASS |
| FR-011 | `agents/audit.nix`, Phase 5 | PASS |
| FR-012 | `tests/os-agents.nix`, Phases 1/2/7 | PASS |
| FR-013 | `agents/coding-agent.nix`, Phase 6 | PASS |
| FR-014 | `agents/incidents.nix`, Phase 6 | PASS |
| FR-015 | `agents/mcp.nix`, Phase 4 | PASS |

| NFR ID | Plan Coverage | Status |
|--------|--------------|--------|
| NFR-001 (Observability) | `agent-desktops.target` in desktop.nix, audit.nix | PASS |
| NFR-002 (Isolation) | Security Considerations table, Phase 7 tests | PASS |
| NFR-003 (Declarative) | Core design throughout; mirrors users.nix pattern | PASS |
| NFR-004 (Resource Limits) | Config example has `resources = {}` but no plan file owns the wiring | WARN |

**NFR-004 Note**: The `resources` option (cpuQuota, memoryMax) appears in the spec's config example and is tested in Phase 7 (cgroup limits), but no plan file is explicitly responsible for implementing the systemd resource control wiring. Recommendation: Add resource limit wiring to `agents/users.nix` (Task 1) since it owns the user service configuration.

### Plan → Tasks Traceability

| Plan File | Task(s) | Status |
|-----------|---------|--------|
| `modules/os/agents.nix` | Task 1 | PASS |
| `modules/os/agents/default.nix` | Task 1 | PASS |
| `modules/os/agents/users.nix` | Task 1 | PASS |
| `modules/os/agents/secrets.nix` | Task 1 | PASS |
| `modules/os/agents/desktop.nix` | Task 3 | PASS |
| `modules/os/agents/chrome.nix` | Task 4 | PASS |
| `modules/os/agents/mail.nix` | Task 5 | PASS |
| `modules/os/agents/bitwarden.nix` | Task 6 | PASS |
| `modules/os/agents/tailscale.nix` | Task 7 | PASS |
| `modules/os/agents/ssh.nix` | Task 8 | PASS |
| `modules/os/agents/agent-space.nix` | Task 9 | PASS |
| `modules/os/agents/mcp.nix` | Task 10 | PASS |
| `modules/os/agents/task-loop.nix` | Task 11 | PASS |
| `modules/os/agents/audit.nix` | Task 12 | PASS |
| `modules/os/agents/coding-agent.nix` | Task 13 | PASS |
| `modules/os/agents/incidents.nix` | Task 14 | PASS |
| `modules/os/agents/scripts/scaffold-agent-space.sh` | Task 9 | PASS |
| `modules/os/agents/scripts/task-loop.sh` | Task 11 | PASS |
| `modules/os/agents/scripts/audit-logger.sh` | Task 12 | PASS |
| `modules/os/agents/scripts/coding-agent.sh` | Task 13 | PASS |
| `tests/os-agents.nix` | Tasks 2, 15, 16 | PASS |
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

All 15 FRs use RFC 2119 keywords (MUST, MUST NOT, SHALL, SHOULD, MAY) in uppercase. No informal priority labels detected. PASS.

### Unresolved Markers

| File | Location | Marker | Context |
|------|----------|--------|---------|
| spec.md | Open Questions §1-3 | Open Question | Resolved in plan.md (Cage, wayvnc, Chrome) but not formally closed in spec |
| spec.md | Open Questions §4 | Open Question | Agent-to-agent communication — not addressed in plan or tasks |
| spec.md | Open Questions §5 | Open Question | Lifecycle CLI — not addressed in plan or tasks |

No `[TBD]`, `[TODO]`, `???`, or empty sections found in any file.

**Note**: Open Questions 4 and 5 are genuinely out of scope for the current implementation (explicitly listed as "Future Considerations" territory). Questions 1-3 were design decisions made during planning — they could be formally closed in spec.md by moving the chosen answers inline and removing the questions.

### Over-Engineering Check

| Item | Traces To | Status |
|------|-----------|--------|
| All plan components | FR-001 through FR-015 | PASS |
| All tasks | Corresponding FRs | PASS |
| All scripts | Parent module FRs | PASS |

No gold-plating detected.

### Dependency Integrity

- **Circular references**: None
- **Parallel marker conflicts**: None — all `[P]` tasks modify unique files
- **Checkpoint coverage**: Complete — all 7 phases have checkpoints with verifiable criteria
- **Shared test file**: Parallel tasks extend `tests/os-agents.nix` via validation steps, but this is sequential merge work, not a true parallel conflict (test additions are additive)

## Recommendations

1. **NFR-004**: Explicitly add resource limit wiring (systemd `CPUQuota`, `MemoryMax`) to Task 1's acceptance criteria, since `agents/users.nix` owns the user service definition.
2. **Open Questions 1-3**: Optionally close these in spec.md by documenting the plan.md decisions inline (Cage default, wayvnc, Chrome). Not blocking.
3. **Open Questions 4-5**: Leave as-is — these are future scope, not current implementation gaps.
