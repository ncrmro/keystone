# Current Work: Hyprland Config Fixes for Mac

## Goal
Fix all Hyprland configuration errors on the Mac host (192.168.1.64) running Keystone desktop with Hyprland 0.52.

## Current Progress

### Completed
1. **Fixed windowrule syntax** in `modules/desktop/home/hyprland/layout.nix`:
   - Changed boolean values from `1` to `on` (e.g., `float on`, `fullscreen on`)
   - Removed invalid rules: `suppressevent`, `tile`, `nofocus`, `stayfocused`, `initialClass`
   - Using correct 0.52+ syntax: `"float on, match:class ^(steam)$"`

2. **Fixed layerrule syntax** in `modules/desktop/home/components/screenshot.nix`:
   - Changed `noanim, slurp` to `noanim on, slurp` (just committed)
   - Hyprland 0.52+ requires values for boolean rules in layerrules too

3. **Committed fix**: `8b818bb` - "fix(desktop/hyprland): add 'on' value to noanim layerrule"

### In Progress
- **Deploying to Mac**: Rsync'd files to Mac, but hit socket file error
- Need to clean socket files and run `nixos-rebuild switch`

## Next Steps
1. Clean socket files on Mac: `ssh root@192.168.1.64 "find /etc/nixos -type s -delete"`
2. Run switch: `ssh root@192.168.1.64 "nixos-rebuild switch --flake /etc/nixos#keystone-mac --impure"`
3. Reboot Mac to verify no more Hyprland config errors
4. If `noanim on` doesn't work, try alternative syntaxes from Hyprland docs

## Context

### Hyprland 0.52 Syntax Changes
- **Windowrules** use new syntax with `match:` prefix: `"float on, match:class ^(steam)$"`
- **Layerrules** use OLD syntax without `match:` prefix: `"noanim on, slurp"`
- Boolean values need `on`/`off` instead of `1`/`0`

### Key Files Modified
- `/home/ncrmro/code/ncrmro/keystone/modules/desktop/home/hyprland/layout.nix` - windowrules
- `/home/ncrmro/code/ncrmro/keystone/modules/desktop/home/components/screenshot.nix` - layerrule for slurp

### Mac Host Details
- IP: 192.168.1.64
- Config: `keystone-mac`
- Hyprland version: 0.52.0 (commit 75f6435)

### Background Processes
Multiple background SSH sessions running on Mac - may need cleanup before rebuilding.

## Pending Task from User
User asked to "leave a TODO in nixos-config/home-manager/ncrmro/base.nix" indicating those rules can be removed after migration - THIS WAS NOT DONE YET.

## Sources
- [Hyprland 0.52 breaking changes discussion](https://github.com/hyprwm/Hyprland/discussions/12607)
- [Layerrule noanim issue](https://github.com/hyprwm/Hyprland/issues/7524)
