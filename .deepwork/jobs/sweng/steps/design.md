# Architecture Design

## Objective

Explore the target codebase, understand existing architecture and constraints, and produce
an architecture/design document with diagrams, trade-offs, and implementation recommendations.
This step is standalone — no code changes are made.

## Task

### Process

#### Step 1: Gather Inputs

If the goal and repo were provided when the workflow was started (via the workflow goal
or user prompt), skip to Step 2. Only ask structured questions if inputs are missing
or ambiguous:

- **goal**: What feature, system change, or architectural question to address
- **repo**: Target repository as `owner/repo`

If the goal is vague, ask clarifying questions:

- What problem does this solve?
- Who is the audience for this design?
- Are there specific constraints (performance, backwards compatibility, timeline)?

#### Step 2: Locate or Explore the Repo

Since this is a read-only design step (no code changes), full cloning to `.repos/` is
not required. Use whatever method gets you codebase access fastest:

1. **Check if already available locally**: `ls .repos/OWNER/REPO 2>/dev/null`
2. **Use GitHub/Forgejo API for quick exploration**: `gh repo view`, `gh api`
3. **Clone temporarily if needed**: `gh repo clone OWNER/REPO /tmp/REPO` for exploration
4. **Or clone per convention if you expect follow-up implementation**:
   ```bash
   # GitHub:
   gh repo clone OWNER/REPO .repos/OWNER/REPO
   # Forgejo:
   git clone ssh://forgejo@git.ncrmro.com:2222/OWNER/REPO.git .repos/OWNER/REPO
   ```

#### Step 3: Explore the Codebase

Build understanding of the existing architecture:

1. **Read project context**: `AGENTS.md`, `CLAUDE.md`, `README.md`
2. **Understand the tech stack**: `flake.nix`, `package.json`, `Cargo.toml`, etc.
3. **Map the module structure**: directory layout, entry points, key abstractions
4. **Identify integration points**: APIs, database schemas, external services
5. **Review existing patterns**: how similar features are implemented

Focus on areas relevant to the design goal. Do NOT read the entire codebase — be targeted.

#### Step 4: Identify Constraints

Document hard constraints that the design must respect:

- **Existing conventions**: coding style, naming, module boundaries
- **Infrastructure**: deployment targets, runtime environment, performance budgets
- **Backwards compatibility**: APIs, data formats, user-facing behavior
- **Dependencies**: what can be added vs what's locked

#### Step 5: Design the Solution

Produce a design that addresses the goal:

1. **Problem statement**: what needs to change and why
2. **Proposed approach**: the recommended design
3. **Architecture diagram**: ASCII diagram showing components and data flow
4. **Alternatives considered**: at least 2 alternatives with pros/cons
5. **Trade-offs**: what the chosen approach gains and sacrifices
6. **Implementation plan**: ordered steps that could feed into the `implement` workflow
7. **Open questions**: unknowns that need resolution before implementation

#### Step 6: Write the Design Document

Write `design_doc.md` to `.deepwork/tmp/sweng/design_doc.md`:

```bash
mkdir -p .deepwork/tmp/sweng
```

## Output Format

### design_doc.md

```markdown
# Design: [Title]

## Problem Statement

[What needs to change and why. Reference the goal provided by the user.]

## Context

- **Repository**: owner/repo
- **Tech stack**: [from project files]
- **Affected modules**: [list of modules/files that would change]

## Proposed Design

[Detailed description of the recommended approach]

### Architecture Diagram
```

[ASCII diagram showing components, data flow, or module interactions]

```

### Key Decisions

1. [Decision]: [Chosen approach] because [rationale]
2. [Decision]: [Chosen approach] because [rationale]

## Alternatives Considered

### Alternative A: [Name]

[Description]

**Pros**: [list]
**Cons**: [list]
**Why not**: [reason]

### Alternative B: [Name]

[Description]

**Pros**: [list]
**Cons**: [list]
**Why not**: [reason]

## Trade-offs

| Aspect | Gain | Sacrifice |
|--------|------|-----------|
| [aspect] | [what we get] | [what we give up] |

## Implementation Plan

1. [Step 1 — what to change and where]
2. [Step 2]
3. [Step 3]

Estimated scope: [number of files, rough complexity]

## Open Questions

- [ ] [Question that needs resolution before implementation]
```

## Quality Criteria

- The problem statement clearly explains what needs to change and why
- At least one ASCII diagram illustrates the proposed architecture or data flow
- At least 2 alternatives are considered with concrete pros/cons
- Design decisions include rationale for the chosen approach
- Implementation plan has concrete, ordered steps that reference specific files
- Design respects existing codebase constraints and conventions
- Open questions are identified rather than silently assumed

## Context

This step produces a design document that can stand alone (for discussion/review)
or feed into the `implement` workflow. The design is NOT code — it's a plan.
A good design document saves implementation time by resolving ambiguity upfront.
