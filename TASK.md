---
repo: ncrmro/keystone
branch: feat/demo-presentations
agent: claude
platform: github
issue: 203
task_type: implement
status: assigned
created: 2026-03-23
---

# Standardize Demo/Presentation Recording and Slidev Integration

## Description

Create documentation and tooling for standardized demo/presentation workflows in keystone.
There are four distinct use cases, each with different tools:

1. **Quick PR/bug demos** — `keystone-screenrecord` (already exists)
2. **Slide-based presentations** — Slidev (needs packaging/docs)
3. **Long-form tutorials/streaming** — OBS (needs docs)
4. **Video-to-Slidev post-processing** — `video-slidev` (needs docs)

The primary deliverable is `docs/desktop/presentations.md` that describes each scenario
and when to use each tool. Secondary deliverables are Slidev packaging and DeepWork
workflows for presentation creation.

Tech stack: NixOS modules, Nix overlays, home-manager, DeepWork jobs (YAML + markdown).

## Acceptance Criteria

- [x] `docs/desktop/presentations.md` exists covering all four use case scenarios
- [x] Slidev is packaged or has a documented setup path
- [x] OBS usage is documented as an alternative for complex recordings
- [x] `video-slidev` pipeline is documented with usage examples
- [ ] At least one DeepWork workflow for presentation creation exists (deferred — outline posted on #203)
- [ ] Existing evaluation passes (`nix flake check --no-build`)

## Key Files

- `docs/desktop/screen-recording.md` — existing recording docs (reference for style)
- `docs/desktop/presentations.md` — new file to create
- `modules/desktop/home/scripts/default.nix` — existing screenrecord script
- `modules/desktop/nixos.nix` — desktop NixOS options
- `overlays/default.nix` — overlay packages
- `.deepwork/jobs/` — DeepWork job definitions
