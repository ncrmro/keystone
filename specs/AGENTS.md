# Specs folder guide (`specs/`)

This directory contains the repository's normative requirements and design
artifacts.

## Layout

All active specs are flat Markdown files at the top of `specs/`. There are
no subdirectories for active specs.

- `REQ-NNN-slug.md` — canonical requirement specs (e.g., `REQ-023-executive-assistant-perception-layer.md`)
- `NNN-slug.md` — legacy numbered specs predating the REQ prefix; treat as read-only
- `_archive/` — retired multi-file feature planning folders; historical only

## File naming

All new specs MUST be flat files at `specs/REQ-NNN-slug.md`. Do NOT create
subdirectories with `requirements.md` inside them. The next available number
is `REQ-032`.

## Editing rules

1. All active specs are flat `REQ-NNN-slug.md` files — never a directory with
   `requirements.md` inside it.
2. To create a new spec: add `specs/REQ-NNN-slug.md` using the next available
   number. Check existing files first to confirm the number is free.
3. `_archive/` is historical only. Do not add new active specs there.
4. Cross-reference related specs by requirement ID in the document body when
   behavior spans multiple domains.

## Numbering

1. New `REQ-*` specs MUST use the next available requirement number. Current
   highest is `REQ-031` — next new spec is `REQ-032`.
2. A new focused requirement should get its own `REQ-*` file even when split
   out from a broader spec.
3. Revisions to an existing spec keep the same `REQ-*` number when scope is
   still fundamentally the same.
4. Note: `REQ-002`, `REQ-021`, and `REQ-024` each have two files with different
   slugs — known numbering collisions from legacy migration. Do not reuse those
   numbers for new unrelated specs.

## Verification

1. Spec changes still require repository-level verification with `ks build`.
2. Keep prose concise, normative, and traceable to the surrounding specs.
