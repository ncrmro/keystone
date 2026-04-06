# Experimental features

Keystone uses stability tiers to set expectations for each module. Features
marked **experimental** are functional but may change significantly in future
releases. They are not part of the stable v1 surface.

## What experimental means

- The feature works and is usable today.
- The API (options, CLI flags, file formats) may change without a migration path.
- The feature may be restructured, renamed, or removed in a future release.
- Bug reports are welcome but fixes are lower priority than stable features.

## The `keystone.experimental` flag

All experimental modules are gated behind a single boolean:

```nix
keystone.experimental = true;  # opt in to experimental features
```

**Module**: `modules/shared/experimental.nix` — zero-dependency, imported by
every module layer (NixOS, home-manager). Nix deduplicates identical imports.

When `keystone.experimental = true`, experimental modules auto-enable (their
`enable` option defaults to `true`). When `false` (the default), they stay
disabled unless explicitly enabled.

### For module authors

To mark a module as experimental:

1. Import `../shared/experimental.nix` in the module.
2. Default the `enable` option to `config.keystone.experimental`:
   ```nix
   enable = lib.mkOption {
     type = lib.types.bool;
     default = config.keystone.experimental;
     description = "Enable <feature> (EXPERIMENTAL).";
   };
   ```
3. Add `[EXPERIMENTAL]` to the module file header comment.
4. Add an entry to this document.

## Stability tiers

| Tier | Meaning |
|------|---------|
| **Stable** | Part of the v1 surface. Breaking changes require a migration path. |
| **Experimental** | Gated behind `keystone.experimental`. Marked with `[EXPERIMENTAL]` in module headers. |

## Experimental features

### `keystone.notes` — Git-backed notebook sync

**Module**: `modules/notes/default.nix`
**Milestone**: [v2 — Un-experimental](https://github.com/ncrmro/keystone/milestone/10)

Syncs a git-backed notes repository on a timer using `repo-sync`. Optionally
initializes a zk Zettelkasten notebook structure with templates, directories,
and LSP integration.

**Why experimental**: The notes module was originally the source of truth for
project discovery. With the move to declarative `projects.yaml`, the notes
module's role is shifting to pure knowledge management. The option surface and
zk integration may be restructured.

**Options affected**:
- `keystone.notes.enable`
- `keystone.notes.repo`
- `keystone.notes.path`
- `keystone.notes.syncInterval`
- `keystone.notes.commitPrefix`
- `keystone.notes.sync.enable`
- `keystone.notes.zk.enable`

### `archetypes.yaml` — Agent instruction composition

**File**: `conventions/archetypes.yaml`
**Milestone**: [v2 — Un-experimental](https://github.com/ncrmro/keystone/milestone/10)

Defines agent archetypes with inlined and referenced conventions that compose
into system prompts for AI coding agents. The `conventions.nix` module
regenerates instruction files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) from
archetypes during `ks build` and `ks update --dev`.

**Why experimental**: The archetype schema, convention composition model, and
generated file format are actively evolving. Role definitions and convention
assignment patterns may change.

## Stable v1 surface

The following are considered stable:

- **OS modules**: storage (ZFS), secure boot, TPM, users, agents, SSH
- **Terminal modules**: shell, editor, AI, git, projects, deepwork
- **Desktop modules**: Hyprland, walker, project menus, theming
- **Server modules**: services, DNS, ACME, nginx, Forgejo, monitoring
- **Project config**: `projects.yaml` (JSON schema validated)
- **CLI tools**: `ks` (build/update/switch/doctor), `pz` (sessions/menus)
- **Shared options**: `keystone.repos`, `keystone.development`, `keystone.hosts`

## Graduating from experimental

To move a feature from experimental to stable (targeted for v2):

1. Freeze the option surface — no breaking changes without migration.
2. Add comprehensive flake checks covering the feature's contract.
3. Document the feature in `docs/`.
4. Remove the `[EXPERIMENTAL]` marker from the module header and options.
5. Close the corresponding milestone issue.
