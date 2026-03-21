# Write Issue

## Objective

Produce a complete keystone specification document with RFC 2119 requirements, a user story, affected modules, and ASCII architecture diagrams. The spec follows the established pattern in `specs/`.

## Task

Take the user's feature description and research the keystone codebase to produce a well-structured spec. Ask structured questions if the description is ambiguous.

### Process

1. **Understand the feature**
   - Parse the user's feature description
   - Ask structured questions to clarify scope, affected hosts, and integration points
   - Identify which existing keystone modules are involved

2. **Research the codebase**
   - Read the relevant modules in `modules/` to understand current architecture
   - Check if similar patterns exist (e.g., how other server services are structured)
   - Review `AGENTS.md` / `CLAUDE.md` for the module file tree and conventions
   - Look at existing specs in `specs/` for format reference — especially the most recent ones

3. **Determine the next REQ number**
   - List `specs/` to find the highest REQ number
   - Increment by 1 for the new spec

4. **Write the spec**
   - Follow the established format (see Output Format below)
   - Use RFC 2119 keywords: MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT, MAY, REQUIRED, OPTIONAL
   - Every requirement MUST be numbered: `REQ-XXX.N`
   - Include at least one ASCII diagram showing module architecture or data flow
   - Identify all affected files in `modules/`, `packages/`, and `flake.nix`

5. **Create the spec directory and file**
   - Create `specs/REQ-XXX-<short-name>/requirements.md`
   - The short name should be lowercase-hyphenated, matching the feature (e.g., `journal-remote`)

## Output Format

### requirements.md

```markdown
# REQ-XXX: <Feature Title>

<One paragraph summary of what this feature does and why it matters.>

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a [role], I want [capability] so that [benefit].

## Architecture

```
[ASCII diagram showing module relationships, data flow, or system topology]
```

## Affected Modules
- `modules/path/to/file.nix` — [what changes]
- `modules/path/to/other.nix` — [what changes]

## Requirements

### <Section Name>

**REQ-XXX.1** <Module/feature> MUST <do something specific>.

**REQ-XXX.2** <Module/feature> SHOULD <do something recommended>.

**REQ-XXX.3** When <condition>, <module> MUST <behavior>.

[Continue with numbered requirements grouped by logical section...]

### Configuration

**REQ-XXX.N** The module MUST expose options at `keystone.<path>`.

```nix
# Example configuration
keystone.<path> = {
  enable = true;
  # ... options with descriptions
};
```

### Integration

**REQ-XXX.N** <How this integrates with existing keystone modules.>

### Security

**REQ-XXX.N** <Security considerations, if applicable.>
```

## Quality Criteria

- Requirements use RFC 2119 keywords correctly and consistently
- Each requirement is numbered and specific enough to verify
- At least one ASCII diagram illustrates the architecture
- All affected keystone modules and files are identified
- A user story or motivation section explains why this feature matters
- The spec follows the format of existing specs in `specs/`

## Context

Keystone specs live in `specs/REQ-XXX-<name>/requirements.md`. They serve as the plan of record for implementation. The `ks.develop` workflow consumes these specs as input goals. Well-written specs with clear RFC 2119 requirements make implementation and review much smoother.
