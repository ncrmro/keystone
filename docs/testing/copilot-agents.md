---
title: Copilot agent guide for ISO e2e validation
description: Practical workflow for building and validating Keystone ISO + headful desktop screenshots
---

# Copilot agent guide for ISO e2e validation

This guide is the shortest reliable path for validating the full Keystone flow:

1. Build ISO
2. Install in VM
3. Reboot installed disk
4. Capture LUKS + hyprlock + desktop screenshots
5. Compare against Git LFS baselines

## Baseline validation

From the keystone repository root (for GitHub Actions, this is typically
`$GITHUB_WORKSPACE`, often `/home/runner/work/keystone/keystone`):

```bash
nix flake check --no-build
nix flake check
```

## Canonical e2e command

Run from a template consumer repo (fixture) that has `bin/test-iso`:

```bash
./bin/test-iso --dev --e2e --port 12260 --memory 12288
```

- **Headed mode (default)**: virtio-gpu + virgl, screenshot fallback uses `grim` over SSH for real desktop pixels.
- **Headless mode**: add `--headless`, uses llvmpipe + QEMU `screendump` (better for CI without host GPU).

## Fast iteration shortcut (avoid rebuilding ISO)

For most module and template changes, **do not rebuild ISO**:

```bash
nix flake update keystone
./bin/test-iso --dev --e2e --no-build --port 12260 --memory 12288
```

Use full rebuild only when changing installer-baked artifacts (notably `packages/ks/`).

## Screenshot verification contract

- Captures are written to `/tmp/keystone-e2e-screenshots`.
- Baselines are in `templates/default/tests/e2e/screenshots/` (Git LFS tracked).
- Comparison is byte-for-byte (`cmp`); LFS pointer `oid sha256:` is the natural checksum.

Expected key checkpoints:

- `01-luks-prompt`
- `03-hyprlock`
- `04-desktop`

## Known blockers and tuning items

1. **Startup lock denial (`yeeten`)** during greetd → uwsm → Hyprland startup.
   - `yeeten` is hyprlock's session-lock denial path (lock request finished/rejected by compositor).
   - Track `keystone-startup-lock` journal logs and Hyprland debug logs.
   - Validate whether lock dispatch succeeds on cold boot repeatedly.
2. **LUKS screenshot in headed mode** can be unavailable with virgl (`screendump` no surface).
   - Expected fallback behavior: keep LUKS verification in headless CI, use headed `grim` for desktop stages.
3. **nix-serve substituter persistence** must remain in `/etc/nix/conf.d/e2e-local-cache.conf`.
   - Re-validate after any installer/nix-daemon changes.
4. **Template lock hygiene** before release.
   - Ensure template `flake.lock` points to `github:ncrmro/keystone` for release, while local e2e still supports runtime override.

## Minimal verification checklist for PRs touching this flow

- Run `nix flake check` in `/home/runner/work/keystone/keystone`.
- Run one `test-iso --dev --e2e` cycle (headed for desktop screenshot fidelity).
- Confirm `03-hyprlock` and `04-desktop` are captured and compared.
- If failures occur after install, re-run with `--no-build` first before rebuilding ISO.
