---
repo: ncrmro/keystone
branch: feat/first-boot-hardware-fact-detection-225
agent: claude
platform: github
issue: 225
task_type: implement
status: completed
created: 2026-04-08
---

# feat(keystone-tui): add first-boot hardware fact detection and diff preview

## Description

The current first-boot flow runs `nixos-generate-config --show-hardware-config` and writes
the raw output directly to `hardware.nix` without presenting a review step or performing
any reconciliation against the hardware selected during install. The user sees no diff,
no warning about disk mappings, and has no way to skip if detection looks wrong.

This task adds:
1. In-memory hardware facts collection (`FirstBootHardwareFacts`)
2. In-memory patch plan generation (`PushbackPatchPlan`) with diff preview
3. A user-facing review step before any file is written
4. Confident disk mapping with explicit warning if mapping fails
5. A clean "no changes required" exit when hardware.nix already matches

Tech stack: Rust, ratatui, tokio. Source at `packages/keystone-tui/src/`.

## Acceptance Criteria

- [ ] First-boot flow gathers actual hardware facts before proposing repo changes
- [ ] The flow builds an in-memory patch plan instead of writing raw hardware.nix output directly to git
- [ ] The screen shows detected disk identifiers, kernel modules, and a diff preview step before apply
- [ ] If no confident disk mapping exists, the flow warns and does not silently guess
- [ ] If no patch is needed, the flow exits cleanly with an explicit "no changes required" result
- [ ] Existing tests pass (cargo test)

## Key Files

- `packages/keystone-tui/src/screens/first_boot.rs` — first-boot orchestration and phases
- `packages/keystone-tui/src/disk.rs` — disk discovery (reused for fact gathering)
- `packages/keystone-tui/src/template.rs` — placeholder constants consumed during reconciliation
