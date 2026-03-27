# Specs folder guide (`specs/`)

This directory contains the repository's normative requirements and design
artifacts.

## Layout

The folder currently contains a mix of legacy layouts:

- top-level Markdown specs such as `REQ-002-keystone-desktop.md`,
- numbered Markdown specs such as `001-shared-dev-mode-path-resolution.md`,
- newer requirement directories that contain a `requirements.md` file, and
- archived feature-planning folders under `_archive/`.

## Editing rules

Use these rules when adding or updating specs:

1. Treat files named `REQ-*` and numbered top-level Markdown files in `specs/`
   as the canonical current specs.
2. Treat `_archive/` as historical material only. Do not add new active specs
   there.
3. For new active specs, prefer a single top-level Markdown file in `specs/`
   rather than creating a new directory with `requirements.md`.
4. When updating a legacy spec that already lives in a directory, preserve the
   existing structure unless the change explicitly includes a cleanup migration.
5. Cross-reference related specs by requirement ID in the document body when
   behavior spans multiple domains.

## Numbering

1. New `REQ-*` specs MUST use the next available requirement number rather than
   overloading an older spec number with unrelated scope.
2. A new focused requirement should get its own `REQ-*` file even when it is
   split out from an older broader spec.
3. Revisions to an existing spec should keep the same `REQ-*` number when the
   scope is still fundamentally the same.

## Verification

1. Spec changes still require repository-level verification with `ks build`.
2. Keep prose concise, normative, and traceable to the surrounding specs.
