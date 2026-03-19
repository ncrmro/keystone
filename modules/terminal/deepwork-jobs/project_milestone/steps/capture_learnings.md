# Capture Learnings

## Objective

Extract process improvements and key learnings from the completed milestone so the next
one goes better. Write them to `milestones/<milestone-name>/learnings.md`.

## Task

### Step 1: Read Inputs

- Read `milestones/<milestone-name>/outcomes.md` for what was delivered and deferred
- Optionally re-read `milestones/<milestone-name>/blockers.md` if one exists

### Step 2: Reflect on the Milestone

Consider the following questions:

**What worked well?**
- Which workflows or practices helped the team move fast?
- Which types of tasks were completed ahead of schedule?
- What communication or tooling made things easier?

**What didn't work?**
- Where did the team lose time or get stuck?
- Were any estimates significantly off? Why?
- What caused the deferred items?

**What should change?**
- Are there process steps to add, remove, or modify?
- Are there tools or automations that would help?
- Are there scope or planning patterns to avoid next time?

### Step 3: Write learnings.md

Create `milestones/<milestone-name>/learnings.md`:

```markdown
# Learnings: <Milestone Name>

**Date**: <today>

## What Worked Well

- <observation> — *Keep doing this*

## What Didn't Work

- <observation> — *Root cause: <why>*

## Action Items

| Action | Owner | When |
|--------|-------|------|
| <concrete improvement> | <role or name> | next milestone |
...

## Notes

<Anything that doesn't fit above but is worth remembering>
```

### Step 4: Confirm

- At least one "what worked" and one "what didn't" item are captured
- Each action item is specific and has an owner
- File is saved
