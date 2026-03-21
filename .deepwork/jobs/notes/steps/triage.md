# Triage Inbox

## Objective

Process all fleeting notes in `inbox/`, deciding for each: promote to permanent note, promote to literature note, promote to decision record, or discard. After triage, the inbox should be empty (or contain only notes less than 48 hours old).

## Task

### Process

1. **List inbox notes**
   ```bash
   cd "$notes_path"
   zk list inbox -f json
   ```
   - If inbox is empty, write a triage log noting "No notes to process" and exit

2. **For each fleeting note**, read its content and decide:

   **a) Promote to permanent note** (the note contains a reusable insight or learned constraint):
   - Extract the atomic insight (one idea per note)
   - Create a permanent note: `zk new notes --title "{insight title}"`
   - Copy the relevant content, rewriting for clarity and self-containment
   - Search for related notes: `zk list --match "{key terms}"`
   - Add wikilinks to related notes in the Links section
   - Update the author field
   - Delete the fleeting note: `rm inbox/{filename}`
   - Commit: `feat(notes): promote inbox note to permanent - {title}`

   **b) Promote to literature note** (the note summarizes an external source):
   - Create a literature note: `zk new literature --title "Summary of {source}"`
   - Fill in the source field, Summary, Key Points, and Relevance sections
   - Link to any permanent notes it supports
   - Delete the fleeting note
   - Commit: `feat(notes): promote inbox note to literature - {title}`

   **c) Promote to decision record** (the note captures an architectural decision):
   - Create a decision record: `zk new decisions --title "ADR: {decision}"`
   - Fill in Context, Decision, Consequences sections
   - Set status to `proposed` or `accepted` based on content
   - Link to related notes
   - Delete the fleeting note
   - Commit: `feat(notes): promote inbox note to decision - {title}`

   **d) Discard** (the note has no lasting value — transient observation, duplicate, or stale):
   - Delete the fleeting note: `rm inbox/{filename}`
   - Commit: `chore(notes): discard fleeting note - {brief reason}`

3. **Update index notes**
   - If any promoted notes belong to an existing MOC's topic area, add wikilinks to the relevant index note
   - If promoted notes reveal a new topic cluster (3+ related notes without a MOC), create a new index note

4. **Write triage log**

## Output Format

### triage_log.md

Write to `.deepwork/tmp/notes/triage_log.md`:

```markdown
# Inbox Triage Log

**Repository**: {notes_path}
**Date**: {YYYY-MM-DD}
**Author**: {author}
**Notes processed**: {count}

## Actions

| # | Inbox Note | Action | Target | Links Added | Commit |
|---|-----------|--------|--------|-------------|--------|
| 1 | 202603201430 dns-observation.md | promote:permanent | notes/202603211000 dns-resolution-caching.md | [[202603150900]], [[202603180800]] | abc1234 |
| 2 | 202603201445 nix-rfc-42.md | promote:literature | literature/202603211001 summary-nix-rfc-42.md | [[202603100700]] | def5678 |
| 3 | 202603201500 random-thought.md | discard | — | — | ghi9012 |

## Index Updates

| Index Note | Notes Added |
|------------|-------------|
| index/202603151200 moc-dns.md | [[202603211000]] |

## Summary

- {N} promoted to permanent
- {N} promoted to literature
- {N} promoted to decision
- {N} discarded
- {N} index notes updated
- {N} new index notes created
```

## Quality Criteria

- Every `.md` file in `inbox/` was addressed (promoted or discarded)
- Promoted permanent notes are atomic (one idea per note) and self-contained
- Promoted notes include wikilinks to related existing notes (searched via `zk list --match`)
- The inbox is empty after triage (or only contains notes < 48h old)
- Each action is a separate commit

## Context

This is the sole step in the `process_inbox` workflow. Agents SHOULD run this daily to keep the inbox clean. The triage decision (promote vs. discard) requires judgment about whether the captured information has lasting value — when in doubt, promote to permanent rather than discard.
