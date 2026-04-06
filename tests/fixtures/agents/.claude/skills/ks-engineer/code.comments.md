# Convention: Code Comments (code.comments)

Rules for inline and file-level documentation in keystone source files.
Applies to all languages: Nix, Bash, Rust, TypeScript.
See `process.prose` for rules governing non-code narrative text (READMEs, PRs, issues).

## File-Level Documentation

1. Every non-trivial file MUST begin with a comment block explaining:
   - What the module/file does
   - Its security model (if any)
   - Usage examples or entry points

2. For Nix files, use a `#` block at the top before the `{` opening brace.
   See `modules/os/agents/agentctl.nix` as the exemplar.

## Inline Comment Philosophy

3. Comments MUST explain **why**, not **what** — code is self-documenting;
   comments exist to explain decisions that aren't obvious from the code itself.

4. Comments MUST NOT restate what the code does in prose.
   Bad: `# Set enable to true`
   Good: `# enable=true by default so users don't need to opt in (REQ-011)`

## Prefixes

5. `# SECURITY:` — A security-critical design decision. MUST name the specific
   attack vector or threat being mitigated, not a generic description.
   Bad: `# SECURITY: important for safety`
   Good: `# SECURITY: LD_PRELOAD injection — hardcode tool paths, never $PATH`

6. `# CRITICAL:` — A cross-module invariant that breaks silently if violated.
   Use when a constraint is non-obvious and violation causes subtle failures
   elsewhere (not just in this file).

7. `# TODO:` — A known gap. MUST explain the consequence of leaving it unaddressed,
   not just "fix later".
   Bad: `# TODO: fix this`
   Good: `# TODO: missing rate-limit — Stalwart rejects if >5 req/s from same IP`

## What Not to Comment

8. Obvious assignments, simple conditionals, and standard library calls MUST NOT
   be commented — they add noise without value.

9. Commented-out code MUST NOT be committed. Remove dead code; git history preserves it.