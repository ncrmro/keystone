
## Zk (Zettelkasten CLI)

## Notebook Initialization

1. A notes repository MUST be initialized as a zk notebook before use: `zk init`.
2. The `.zk/` directory and its contents (config.toml, templates) MUST be committed to git.
3. Directory structure MUST follow the keystone standard: `inbox/`, `literature/`, `notes/`, `decisions/`, `index/`.
4. See `process.knowledge-management` for the note type taxonomy and methodology.

## Creating Notes

5. Notes MUST be created via `zk new <group>/ --title "Title"`.
6. Groups map to directories: `inbox` (fleeting), `literature`, `notes` (permanent), `decisions`, `index`.
7. In non-interactive contexts (agents, scripts), `--no-input` MUST be used to prevent `$EDITOR` from opening.
8. `--print-path` SHOULD be used when the caller needs the created file path.

```bash
# Human — interactive (opens editor)
zk new notes/ --title "ZFS pool import ordering"

# Agent — non-interactive
zk new inbox/ --title "CI failure pattern" --no-input --print-path

# With extra template variables
zk new literature/ --title "NixOS module system" --no-input \
  --extra source="NixOS Manual" --extra source_url="https://nixos.org/manual"
```

## Searching and Listing

9. Agents MUST use `--format json` for machine-readable output.
10. `--match` performs full-text search across note titles and bodies.

```bash
# Full-text search
zk list --format json --match "ZFS encryption"

# Filter by tag
zk list --format json --tag decision

# Filter by directory (group)
zk list inbox/ --format json

# Find notes linked from a specific note
zk list --linked-by notes/202603201430.md --format json

# Find notes linking to a specific note (backlinks)
zk list --link-to notes/202603201430.md --format json

# Find related notes (shares tags or links)
zk list --related notes/202603201430.md --format json

# Find orphan notes (no incoming or outgoing links)
zk list notes/ --orphan --format json

# Recent notes
zk list --created-after "2 weeks ago" --sort created- --format json
```

## Tags

11. Tags MUST be lowercase, hyphenated slugs (e.g., `nix-modules`, `zfs`, `ci-pipeline`).

```bash
# List all tags with counts
zk tag list

# List notes with a specific tag
zk list --tag zfs --format json
```

## LSP Integration

12. The `zk` LSP server is configured in helix via the keystone terminal module.
13. The LSP activates automatically when helix detects a `.zk/` directory in the workspace.
14. LSP provides: wikilink completion, tag completion, dead-link diagnostics, and note hover previews.
15. Agents SHOULD NOT rely on the LSP — use `zk list` and `zk tag list` for programmatic access.

## Nix-Managed Configuration

16. The `zk` binary is provided by `keystone.terminal.enable` — it is always on `PATH`.
17. The `.zk/config.toml` lives in the notes git repo, NOT in `/nix/store/`. It MAY be edited directly.
18. Template files in `.zk/templates/` MAY be customized per-repo.
