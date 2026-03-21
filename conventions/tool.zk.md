<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
## zk — Zettelkasten Note Management

CLI tool for managing a Zettelkasten-style knowledge base. Notes are plain Markdown files with YAML frontmatter, organized by type and linked via wikilinks.

## Notebook Structure

1. A zk notebook MUST follow this directory layout:

```
notes-repo/
  .zk/config.toml        # zk configuration
  .zk/templates/          # Note templates
  inbox/                  # Fleeting notes (ephemeral)
  literature/             # Source summaries
  notes/                  # Permanent atomic notes
  decisions/              # Architecture Decision Records
  index/                  # Maps of Content
```

2. `TASKS.yaml` at the repo root MUST NOT be managed by zk — it is operational state owned by the task loop.

## Note IDs and Filenames

3. Note IDs MUST use 12-digit timestamps: `YYYYMMDDHHmm` (e.g., `202603201430`).
4. Filenames MUST follow the pattern `{id} {title-slug}.md` (e.g., `202603201430 zfs-encryption-key-rotation.md`).
5. Slugs MUST be lowercase, hyphen-separated, and ASCII-only.

## Frontmatter

6. Every note MUST include YAML frontmatter with these required fields:

```yaml
---
id: "202603201430"
title: "ZFS Encryption Key Rotation"
type: fleeting | literature | permanent | decision | index
created: "2026-03-20T14:30:00Z"
author: agent-drago | ncrmro
tags:
  - zfs
  - encryption
---
```

7. The `type` field MUST match the directory the note resides in.
8. The `author` field MUST match the agent name from `SOUL.md` or the human username.

## Linking

9. Notes MUST be linked using wikilinks: `[[202603201430]]`.
10. Wikilinks MUST reference the note ID only — not the filename or title.
11. Backlinks are resolved automatically by `zk` — agents MUST NOT maintain manual backlink sections.

## Creating Notes

```bash
# Create a fleeting note in inbox/
zk new inbox --title "Quick observation about DNS resolution"

# Create a permanent note in notes/
zk new notes --title "ZFS encryption key rotation"

# Create a literature note from a source
zk new literature --title "Summary of NixOS RFC 42"

# Create a decision record
zk new decisions --title "ADR: Use ZFS native encryption over LUKS"

# Create an index (Map of Content)
zk new index --title "MOC: Storage Architecture"
```

12. Notes MUST be created via `zk new <group> --title "..."` to ensure correct ID generation and template application.
13. Agents MUST NOT create note files manually — always use `zk new`.

## Listing and Searching

```bash
# List all notes
zk list

# List notes in a specific group
zk list inbox
zk list notes

# Search by tag
zk list --tag encryption

# Full-text search
zk list --match "key rotation"

# List notes linked from a specific note
zk list --linked-by 202603201430

# List notes linking to a specific note
zk list --link-to 202603201430

# List orphan notes (no incoming links)
zk list --orphan

# JSON output for scripting
zk list -f json
```

14. List and search commands SHOULD use `-f json` when output is consumed by scripts or agents.

## Editing

```bash
# Open a note by ID
zk edit 202603201430

# Open notes matching a query
zk edit --match "DNS resolution"
```

## Graph and Diagnostics

```bash
# Show link graph statistics
zk graph --format json

# Show tags
zk tag list
```

## LSP Integration

15. `zk` provides a built-in LSP server (`zk lsp`) for wikilink completion, hover previews, and go-to-definition in editors.
16. The LSP server is configured in Helix via `modules/terminal/editor.nix` — agents MUST NOT start `zk lsp` manually.

## Nix-Managed Config

17. The `.zk/config.toml` and `.zk/templates/` are scaffolded by the `keystone.notes.zk.enable` option. If the notebook is Nix-managed, templates in the Nix store MUST NOT be edited directly.
18. For non-Nix-managed repos, `zk init` MAY be used to bootstrap, but the keystone DeepWork `notes/init` workflow is preferred.
