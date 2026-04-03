---
title: Screenshots
description: Capture screenshots on Keystone Desktop, sync them to ocean, and search them through Immich OCR
---

# Screenshots

Keystone Desktop includes a screenshot workflow built on `grim`, `slurp`, and
`satty`.

By default, screenshots are written to `KEYSTONE_SCREENSHOT_DIR`, then
`XDG_PICTURES_DIR`, then `~/Pictures`.

## Capture

The default screenshot command is `keystone-screenshot`.

Common ways to use it:

- `Print` starts a screenshot capture flow.
- `Shift+Print` captures a smart screenshot to the clipboard.
- `keystone-screenshot` runs the default smart mode.
- `keystone-screenshot region` captures a selected region.
- `keystone-screenshot windows` captures a window rectangle.
- `keystone-screenshot fullscreen` captures the focused monitor.

In the save flow, Keystone writes PNG files with names like:

```text
screenshot-2026-04-03_06-23-00.png
```

## Local storage

Keystone resolves the screenshot output directory in this order:

1. `KEYSTONE_SCREENSHOT_DIR`
2. `XDG_PICTURES_DIR`
3. `~/Pictures`

To inspect the current effective location:

```bash
[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
printf '%s\n' "${KEYSTONE_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"
```

## Current stopgap sync flow

The full declarative Keystone implementation is still tracked in issue
[#279](https://github.com/ncrmro/keystone/issues/279).

Until that lands, the current stopgap is a local helper script:

```bash
bash ~/.local/bin/keystone-screenshot-rsync-stopgap --dry-run --verbose
```

The script:

- reads screenshots from `KEYSTONE_SCREENSHOT_DIR`, `XDG_PICTURES_DIR`, or `~/Pictures`
- syncs them to `ocean.mercury` with `rsync --ignore-existing`
- defaults to the canonical target layout:

```text
/ocean/users/$USER/hosts/$(hostname)/Pictures
```

Current options:

```bash
bash ~/.local/bin/keystone-screenshot-rsync-stopgap --help
```

Common usage:

```bash
# Preview what would sync
bash ~/.local/bin/keystone-screenshot-rsync-stopgap --dry-run --verbose

# Sync to the current stopgap path validated on ocean
bash ~/.local/bin/keystone-screenshot-rsync-stopgap \
  --verbose \
  --target-dir /ocean/media/users/ncrmro/hosts/ncrmro-workstation/Pictures
```

## Immich OCR search

After screenshots are on `ocean`, they still need to be visible to Immich.

Current manual flow:

1. Add the screenshot directory in Immich as an external library.
2. Trigger a scan or wait for indexing.
3. Confirm the screenshot appears in Immich.
4. Search for known text from the screenshot in the Immich UI.
5. Configure local Immich credentials and use `ks photos search`.

Example:

```bash
export IMMICH_URL="https://photos.ncrmro.com"
export IMMICH_API_KEY="..."
ks photos search --text "known text from screenshot" --type screenshot
```

## Current caveats

- The canonical target path under `/ocean/users/...` must already exist and be
  writable for the stopgap script's default target to work.
- The currently validated fallback path is `/ocean/media/users/...`.
- The stopgap script is local-only for now. It is not yet a repo-tracked
  Keystone module or packaged desktop command.
- Screenshot OCR search depends on Immich library attachment and indexing, not
  only on the rsync step.

## Related docs

- [Desktop](../desktop.md)
- [Desktop Keybindings](keybindings.md)
- [Screen Recording](screen-recording.md)
