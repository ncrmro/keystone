# Synthesize Daily Priorities

## Objective

Turn calendar pressure, active task notes, and agent activity into a single
ranked plan for the working day.

## Task

Produce a calendar-first priority list. Upcoming meetings, deadlines, and time-
bound commitments outrank nominal project ordering when they conflict.

### Process

1. **Read all inputs**
   - `calendar_context.md`
   - `active_task_notes.md`
   - `agent_activity.md`

2. **Apply the ranking policy**
   - Rank work in this order:
     1. calendar events due today or in the near-term focus window
     2. milestone-linked work that unblocks those calendar events
     3. active delegated work that needs follow-up today
     4. other active milestone work
     5. unscheduled backlog

3. **Choose actions, not just status**
   - For each ranked item, specify:
     - owner
     - next action
     - why it is ranked here
     - whether it should be carried into the daily note

4. **Separate blocked and waiting work**
   - Items waiting on another person, another agent, or an external event should
     remain visible but should not crowd out immediate execution items.

5. **Decide carry-forward set**
   - Identify unfinished items from prior context that should remain active
     today.
   - Identify items that should stay linked for context but not be actively
     carried forward.

## Output Format

### daily_priorities.md

```markdown
# Daily Priorities

- **Working Date**: 2026-03-28

## Ranked Priorities

1. **Prepare investor update**
   - **Owner**: ncrmro
   - **Next Action**: Review drago's milestone draft and finalize talking points by 2026-03-28 12:00.
   - **Why Now**: Supports calendar event at 2026-03-28 14:00.
   - **Carry Forward**: yes

2. **Follow up with luce on demo environment**
   - **Owner**: ncrmro
   - **Next Action**: Send follow-up and create owner mirror once luce repo exists.
   - **Why Now**: Delegated task is blocking today's prep.
   - **Carry Forward**: yes

## Waiting / Blocked

- **Update legal review note**
  - **Status**: waiting
  - **Reason**: Waiting on external counsel response expected 2026-03-29.

## Deferred

- **Backlog grooming for plant-caravan**
  - **Reason**: No calendar pressure inside the current focus window.
```

## Quality Criteria

- Calendar-critical work is ranked above lower-urgency backlog.
- Every ranked item has an owner and a concrete next action.
- Blocked and waiting work stays visible but separate from immediate execution.

## Context

This file becomes the decision engine for the daily note and the sync step. It
must be concise, concrete, and operator-ready.
