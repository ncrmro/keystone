# Keystone Desktop - Keybindings Tasks

This document tracks completed keybinding implementations, conflict resolutions, and implementation history.

## Completed Implementations

### Zellij (Terminal Multiplexer)

Location: `nixos-config/home-manager/common/features/keybindings.nix`

- [x] **Tab Navigation (Ctrl+PgUp/PgDn)**: UHK Mod layer support
- [x] **Tab Navigation (Ctrl+Tab)**: Framework/universal keyboard support
- [x] **New Tab (Ctrl+T)**: Universal support
- [x] **Close Tab (Ctrl+W)**: Universal support
- [x] **Lock Mode Remap**: Ctrl+G -> Ctrl+Shift+G (avoid Claude Code conflict)
- [x] **Session Mode Remap**: Ctrl+O -> Ctrl+Shift+O (avoid Claude Code/Lazygit conflict)

### Ghostty (Terminal Emulator)

Location: `nixos-config/home-manager/common/features/keybindings.nix`

- [x] **Tab Navigation**: Ctrl+Shift+W/E/R/C pattern
- [x] **Unbind Ctrl+PgUp/PgDn**: Pass through to Zellij
- [x] **Unbind Ctrl+Tab**: Pass through to Zellij
- [x] **Unbind Ctrl+Shift+O**: Prevent conflict with Zellij session mode
- [x] **Unbind Ctrl+Alt+Arrows**: Disable pane navigation (Zellij handles panes)

### Helix (Text Editor)

Location: `nixos-config/home-manager/common/features/cli/helix.nix`

- [x] **Return -> :write**: Quick save with Enter key

### Git Aliases

Location: `nixos-config/home-manager/common/features/cli/default.nix`

- [x] `s` -> `switch`
- [x] `f` -> `fetch`
- [x] `p` -> `pull`
- [x] `rff` -> `reset --force`

### Input Configuration

Location: Keystone `modules/keystone/desktop/home/hyprland/input.nix`

- [x] **Caps Lock -> Ctrl**: Remapped via `ctrl:nocaps`

## Conflict Resolutions

### Conflict 1: Ctrl+O - Zellij Session Mode vs Claude Code/Lazygit

**Issue:**
- Zellij Default: `Ctrl+O` enters session mode
- Claude Code: `Ctrl+O` = "view thinking"
- Lazygit: `Ctrl+O` = "copy"

**Impact:** Pressing Ctrl+O in terminal triggers Zellij session mode instead of application-specific actions

**Resolution:** RESOLVED
- Unbinded Zellij's `Ctrl+O` binding
- Remapped session mode to `Ctrl+Shift+O`
- Location: `keybindings.nix:60-65`

**Result:** Claude Code and Lazygit can use Ctrl+O without conflict

---

### Conflict 2: Ctrl+Shift+O - Zellij Session Mode vs Ghostty Split

**Issue:**
- Zellij Custom: `Ctrl+Shift+O` = session mode (after moving from Ctrl+O)
- Ghostty Default: `Ctrl+Shift+O` = `new_split:right` (vertical split)

**Impact:** Pressing Ctrl+Shift+O could trigger both Ghostty split AND Zellij session mode

**Resolution:** RESOLVED
- Unbinded Ghostty's `Ctrl+Shift+O` split binding
- Strategy: Ghostty acts purely as terminal emulator, Zellij handles ALL multiplexing
- Location: `keybindings.nix:93-95`

**Result:** Ctrl+Shift+O reliably opens Zellij session mode, no split conflicts

---

### Conflict 3: Ctrl+Shift+E - Ghostty New Tab vs Ghostty Split

**Issue:**
- Ghostty Default: `Ctrl+Shift+E` = `new_split:down` (horizontal split)
- Ghostty Custom: `Ctrl+Shift+E` = `new_tab` (our configuration)

**Impact:** Dual binding definition could cause unpredictable behavior

**Resolution:** RESOLVED
- Custom `new_tab` binding overrides default split binding
- Documented explicitly in configuration
- Location: `keybindings.nix:78-80`

**Result:** Ctrl+Shift+E creates new Ghostty tab, split functionality disabled

---

### Conflict 4: Ctrl+G - Zellij Lock Mode vs Claude Code

**Issue:**
- Zellij Default: `Ctrl+G` enters locked mode
- Claude Code: `Ctrl+G` = "open prompt in editor"

**Impact:** Pressing Ctrl+G in terminal locks Zellij instead of opening Claude Code editor

**Resolution:** RESOLVED
- Unbinded Zellij's `Ctrl+G` binding
- Remapped lock mode to `Ctrl+Shift+G`
- Location: `keybindings.nix:53-58`

**Result:** Claude Code can use Ctrl+G without triggering Zellij lock mode

## Strategy: Ghostty Splits Disabled

**Decision:** Disable ALL Ghostty split/pane management features

**Rationale:**
1. Single Source of Multiplexing: Zellij provides superior tab AND pane management
2. Avoid Keybinding Conflicts: Prevents collisions with Zellij session/mode bindings
3. Consistent Interface: Users learn ONE multiplexer (Zellij), not two
4. Simplified Mental Model: Ghostty = terminal emulator, Zellij = multiplexer

**Unbinded Ghostty Keybindings:**
- `Ctrl+Shift+O` - new_split:right
- `Ctrl+Alt+Up/Down/Left/Right` - pane navigation

## Pending Tasks

### Hyprland Window Management
- [ ] Implement altwin:swap_alt_win in input.nix
- [ ] Change navigation from Super+H/L to Super+J/K/I/L (home row pattern)
- [ ] Change close window from Super+W to Super+Q

### Terminal Stack
- [ ] Implement Alt+W/E/R/C tab navigation pattern in Zellij
- [ ] Configure Zellij pane navigation with Alt+h/j/k/l

### Helix Enhancement
- [ ] Add LSP operations (go-to-definition, hover, rename, code actions)
- [ ] Add file navigation (file picker, buffer switcher, symbol search)
- [ ] Add multi-cursor workflows

### Browser Integration
- [ ] Export Vimium configuration to version control
- [ ] Configure Alt+W/E/R/C tab navigation in Vimium

### Hardware
- [ ] Document complete UHK layer configuration
- [ ] Test on Framework laptop
- [ ] Test portable keyboard integration

## Changelog

### 2025-12-21
- Added UHK browser navigation documentation
- Documented `Mod + Super + J/L` for browser back/forward (Alt+Left/Right Arrow)
- Added to UHK Mod Layer section and Hardware Translation Table

### 2025-10-25
- Initial KEYBINDINGS.md outline created
- Documented mouse-free workflow philosophy
- Clarified modifier key strategy: Hyprland uses Super, accessed via Alt (swapped via altwin:swap_alt_win)
- Documented current UHK Fn2 layer configuration
- Added Framework laptop portability strategy
- Added portable programmable keyboard section (QMK/ZMK)
- Documented tab navigation pattern (W/E/R/C)
- Created hardware translation table
- Documented ergonomic principles and Caps Lock mouse mode
- Added keybinding consistency matrix
- Outlined 7-phase migration path
- macOS clarifications (Home Manager for cross-platform tools)
- Added Common Workflows & Use Cases section
- Implemented unified tab navigation in keybindings.nix
- Configured Zellij for Ctrl+PgUp/PgDn and Ctrl+Tab
- Disabled Ghostty native tabs (Zellij handles all multiplexing)

## Prevention: How to Avoid Future Conflicts

**Before adding new keybindings:**

1. Check tool defaults: Run `<tool> +list-keybinds --default` (if available)
2. Search existing config: Check `keybindings.nix` for potential conflicts
3. Document the binding: Add comment explaining purpose and any overrides
4. Test in practice: Verify keybinding works as expected in real usage

**Conflict checklist:**
- [ ] Does this conflict with Zellij modes (Ctrl+O, Ctrl+G, Ctrl+P, etc.)?
- [ ] Does this conflict with Claude Code shortcuts?
- [ ] Does this conflict with application-specific bindings (lazygit, helix, etc.)?
- [ ] Is this tool's default behavior being overridden?
- [ ] Should we unbind the default to prevent confusion?
