# Implementation Plan

## Goal
Remove the `[Team]`/`[AgentName]` prefix filter from the calendar scheduler. The calendar itself is the scheduling mechanism — if an event exists on an agent's or team calendar, it should become a task. Replace with minimal structural filtering (skip events missing UID/summary).

## Branch
- **Name**: `fix/calendar-drop-prefix-filter`
- **Worktree**: `.claude/worktrees/fix/calendar-drop-prefix-filter`

## Scope
- **Change type**: OS-level (agent scripts + types)
- **Build strategy**: `nix flake check --no-build` (scripts are template-substituted, no home-manager eval needed for logic change)
- **Affected modules**: `modules/os/agents/scripts/scheduler.sh`, `modules/os/agents/types.nix`, `docs/agents/os-agents.md`

## Validation Criteria

1. `nix flake check --no-build` passes
2. scheduler.sh no longer contains `[Team]` or `[AgentName]` prefix filtering logic
3. Calendar events with any summary (no prefix required) produce tasks
4. Events missing UID or summary are still skipped
5. `calendar.teamEvents` examples/docs no longer mandate `[Team]` prefix convention
6. agent-evaluation test still passes if present

## Steps

### 1. Remove prefix filter from scheduler.sh
- **File**: `modules/os/agents/scripts/scheduler.sh`
- **Change**: Delete the block that checks `$CAL_SUMMARY` against `[Team]*` and `[$AGENT_NAME]*` patterns and skips non-matching events. Keep the UID/summary emptiness check.

### 2. Update types.nix calendar.teamEvents docs
- **File**: `modules/os/agents/types.nix`
- **Change**: Remove references to `[Team]`/`[AgentName]` prefix convention from the `description` and `example` fields. Events are now identified by calendar membership, not name prefix.

### 3. Update docs
- **File**: `docs/agents/os-agents.md`
- **Change**: Remove mentions of prefix filtering. Document that all events on an agent's calendar become tasks.

### 4. Update scheduler.sh comment
- **File**: `modules/os/agents/scripts/scheduler.sh`
- **Change**: Update the section comment from "Events with [Team] or [AgentName] prefixes become tasks" to "All events become tasks".

## Risks
- PR #200 is not yet merged — these changes target main and will need to be applied after PR #200 merges, or submitted as a follow-up PR referencing #200.
- Since PR #200 isn't merged, the calendar code doesn't exist on main yet. We'll need to cherry-pick/recreate the calendar integration minus the prefix filter.
