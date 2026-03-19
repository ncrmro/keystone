# Define Milestone Goals

## Objective

Create a `milestone.md` file that establishes the name, target date, success criteria,
and scope for an upcoming milestone.

## Task

Ask the user (or derive from context) the following information, then write `milestone.md`
into `milestones/<milestone-name>/`.

**Use the AskUserQuestion tool** when information is missing and cannot be inferred from
the project's AGENTS.md, PROJECTS.yaml, or recent commit history.

### Step 1: Gather Milestone Information

Collect the following:

1. **Milestone name** — Short, meaningful label (lowercase with hyphens, e.g. `v1-launch`)
2. **Target date** — When should this milestone be reached?
3. **Goals** — What 2–5 outcomes must be true when this milestone is complete?
4. **Success criteria** — How will you know each goal is done? Make these observable.
5. **In-scope work** — What types of tasks or components are included?
6. **Out-of-scope work** — What is explicitly deferred to a later milestone?

### Step 2: Write milestone.md

Create the file at `milestones/<milestone-name>/milestone.md` with this structure:

```markdown
# Milestone: <Name>

**Target date**: <date>
**Status**: planning

## Goals

1. <Goal 1> — *Done when: <observable criterion>*
2. <Goal 2> — *Done when: <observable criterion>*
...

## Scope

### In scope
- <item>

### Out of scope
- <item>

## Notes

<Any additional context>
```

### Step 3: Confirm

Re-read the file and confirm that:
- Each goal has a concrete "done when" criterion
- The scope section makes tradeoffs explicit
- The file is saved before finishing this step
