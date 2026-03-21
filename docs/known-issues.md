---
layout: default
title: Known Issues
---

# Known Issues

## Development Environment

### `tests/flake.lock` Must Be Kept in Sync with `tests/flake.nix`

**Affects**: `make test-checks`, `make test-module`, `make test-integration`

**Symptom**: Running `nix flake check ./tests` fails with:

```
error: input 'foo' follows a non-existent input 'keystone/foo'
```

**Cause**: When new flake inputs are added to the parent `flake.nix` and referenced in `tests/flake.nix` via `follows`, the `tests/flake.lock` must be updated to include those entries. The lock file does not auto-update.

**Fix**: Run `nix flake lock ./tests --update-input keystone` after adding new inputs to `tests/flake.nix`.

### Test VM Configurations Require `keystone.overlays.default`

**Affects**: `tests/flake.nix` NixOS configurations that import `keystone.nixosModules.operating-system`

**Symptom**: Evaluation fails with:

```
error: attribute 'agenix' missing
at modules/os/default.nix
```

**Cause**: The `operating-system` module uses `pkgs.keystone.*` packages provided by the keystone overlay. Consumer flakes must apply the overlay explicitly.

**Fix**: Add `{ nixpkgs.overlays = [ keystone.overlays.default ]; }` to the modules list of any NixOS configuration that imports `keystone.nixosModules.operating-system`.

### Test VM Configurations Require Tailscale Disabled or `keystone.hosts` Registry

**Affects**: VM test configs with `keystone.os.enable = true` and a custom `networking.hostName`

**Symptom**: Evaluation fails with:

```
Failed assertions:
- Tailscale is enabled but host 'keystone-test-vm' is missing from keystone.hosts registry
```

**Cause**: `keystone.os.tailscale.enable` defaults to `true` when `keystone.os.enable` is set. The Tailscale module requires the host to be registered in `keystone.hosts` with a `role` defined, unless the hostname is the NixOS default (`"nixos"`).

**Fix**: Add `keystone.os.tailscale.enable = false;` to VM test configurations that don't have a `keystone.hosts` registry.

### `make test-template` Requires Network Access

**Affects**: `make test-template`

**Symptom**: Fails with HTTP 403 or DNS errors when trying to fetch flake inputs.

**Cause**: The template test initializes a fresh flake from `templates/default/` which needs to resolve and fetch its own inputs from GitHub. This requires unrestricted network access.

**Workaround**: Use `make test-template-eval` instead, which evaluates the template configuration against local modules without fetching external inputs.

### Upstream Deprecation Warnings During Evaluation

**Affects**: All `nix` commands that evaluate the flake

**Symptom**: Repeated warnings during evaluation:

```
evaluation warning: 'hostPlatform' has been renamed to/replaced by 'stdenv.hostPlatform'
evaluation warning: 'buildPlatform' has been renamed to/replaced by 'stdenv.buildPlatform'
evaluation warning: buildFeatures is deprecated in favour of withFeatures
```

**Cause**: Upstream dependencies (Hyprland, Himalaya, etc.) use deprecated nixpkgs APIs. These warnings are cosmetic and do not affect functionality.

**Status**: Will resolve as upstream dependencies update to newer nixpkgs APIs.

### Nix Stack Size Warning

**Affects**: All `nix` commands

**Symptom**: Warning on every nix invocation:

```
Stack size hard limit is 16777216, which is less than the desired 62914560.
If possible, increase the hard limit, e.g. with 'ulimit -Hs 61440'.
```

**Cause**: The system's default stack size hard limit is below Nix's preferred value. This is a cosmetic warning.

**Workaround**: Add `ulimit -Hs 61440` to your shell profile, or set `DefaultLimitSTACK=62914560` in systemd configuration.

## Runtime

### Zellij: `rename-tab` Targets Wrong Tab with Multiple Clients

**Affects**: `zellij action rename-tab` when multiple clients are attached to the same session

**Symptom**: Running `zellij action rename-tab "name"` renames the other client's focused tab instead of yours.

**Cause**: This is a [confirmed architectural limitation](https://github.com/zellij-org/zellij/pull/3747). CLI actions create a temporary "fake client" connection to the server socket. The fake client has no real focused tab, so the server resolves focus from another connected client.

As maintainer imsnif stated:

> "The CLI is not aware of multiple clients and can never be (because multiple clients being focused on the terminal is a Zellij concept)."

**Related issues**:
- [zellij#4591](https://github.com/zellij-org/zellij/issues/4591) — rename panes/tabs by index
- [zellij#4602](https://github.com/zellij-org/zellij/issues/4602) — rename specific tab by ID
- [zellij#3728](https://github.com/zellij-org/zellij/issues/3728) — NewTab + RenameTab renames wrong tab

**Workaround**: Use the [zellij-tab-name](https://github.com/Cynary/zellij-tab-name) plugin, which uses `$ZELLIJ_PANE_ID` to correctly identify the calling client's tab:

```bash
echo '{"pane_id": "'"$ZELLIJ_PANE_ID"'", "name": "my-tab"}' | zellij pipe --name change-tab-name
```

**Pending fix**: [PR #4594](https://github.com/zellij-org/zellij/pull/4594) adds an explicit `tab_index` parameter to `rename-tab`.
