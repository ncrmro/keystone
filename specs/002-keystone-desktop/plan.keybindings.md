# Keystone Desktop - Keybindings Implementation Plan

This document outlines the implementation strategy for the keybinding requirements defined in `spec.md` (dt-bind-* requirements).

## Current State vs Target State

| Aspect | Current (Keystone) | Target (Spec) | Change Required |
|--------|-------------------|---------------|-----------------|
| Window Navigation | Super+H/L | Super+J/K/I/L | Yes - home row pattern |
| Input Swap | ctrl:nocaps only | altwin:swap_alt_win | Yes - add swap |
| Close Window | Super+W | Super+Q | Yes - free W for tabs |
| Tab Navigation | Not implemented | Alt+W/E/R/C | Yes - new feature |
| Pane Navigation | Not implemented | Alt+h/j/k/l | Yes - new feature |

## Migration Phases

### Phase 1: Documentation & Planning
**Status:** COMPLETE

- [x] Document current state
- [x] Research tool capabilities
- [x] Design unified keybinding scheme
- [x] Create consistency matrix
- [x] Create spec requirements (dt-bind-*)

### Phase 2: Hyprland Foundation
**Status:** PENDING

**Changes to `modules/keystone/desktop/home/hyprland/input.nix`:**
```nix
# Add altwin:swap_alt_win to kbOptions
kbOptions = if cfg.capslockAsControl
  then "ctrl:nocaps,altwin:swap_alt_win"
  else "compose:caps,altwin:swap_alt_win";
```

**Changes to `modules/keystone/desktop/home/hyprland/bindings.nix`:**
```nix
# Change navigation from H/L to J/K/I/L
bind = [
  "$mod, J, movefocus, l"   # Was: $mod, H
  "$mod, K, movefocus, d"   # Was: $mod, J (already exists for different purpose)
  "$mod, I, movefocus, u"   # New
  "$mod, L, movefocus, r"   # Was: $mod, L (same)

  # Change close window from W to Q
  "$mod, Q, killactive"     # Was: $mod, W
];
```

**Tasks:**
- [ ] Add altwin:swap_alt_win to input.nix
- [ ] Update bindings.nix with J/K/I/L navigation
- [ ] Change close window to Super+Q
- [ ] Test on Framework laptop
- [ ] Test with UHK

### Phase 3: Terminal Stack
**Status:** PARTIAL (Zellij/Ghostty configured in nixos-config)

**Current Implementation (in nixos-config):**
- Location: `home-manager/common/features/keybindings.nix`
- Zellij tab navigation: Ctrl+PgUp/PgDn, Ctrl+Tab
- Ghostty unbindings: Pass-through to Zellij
- Mode remapping: Ctrl+G/O -> Ctrl+Shift+G/O

**Remaining Tasks:**
- [ ] Add Alt+W/E/R/C tab navigation to Zellij
- [ ] Add Alt+h/j/k/l pane navigation to Zellij
- [ ] Migrate keybindings.nix to Keystone module
- [ ] Test Ghostty + Zellij integration

### Phase 4: Editor Enhancement
**Status:** MINIMAL

**Current Implementation:**
- Location: `home-manager/common/features/cli/helix.nix`
- Only: Return -> :write

**Remaining Tasks:**
- [ ] Add LSP operations (gd, gr, K for hover)
- [ ] Add file navigation (Space+f for file picker)
- [ ] Add buffer switching
- [ ] Add multi-cursor workflows
- [ ] Migrate to Keystone terminal module

### Phase 5: Browser Integration
**Status:** NOT STARTED

**Tasks:**
- [ ] Export Vimium configuration
- [ ] Store config in version control
- [ ] Document import process
- [ ] Configure Alt+W/E/R/C mappings in Vimium

### Phase 6: Hardware Optimization
**Status:** DOCUMENTED ONLY

**Tasks:**
- [ ] Document complete UHK layer configuration
- [ ] Test Framework laptop workflow
- [ ] Test portable keyboard integration
- [ ] Document MacBook workflow (separate WM)

### Phase 7: Testing & Iteration
**Status:** NOT STARTED

**Tasks:**
- [ ] Daily usage testing (mouse-free workflows)
- [ ] Verify muscle memory portability (UHK <-> Framework)
- [ ] Identify and resolve conflicts
- [ ] Measure productivity improvements
- [ ] Document lessons learned

## Module Architecture

### Keystone Modules (Target)

```
modules/keystone/
├── desktop/home/hyprland/
│   ├── bindings.nix      # dt-bind-010, dt-bind-011, dt-bind-012
│   └── input.nix         # dt-bind-002 (altwin:swap_alt_win)
└── terminal/
    ├── zellij.nix        # dt-bind-020, dt-bind-021, dt-bind-022
    ├── ghostty.nix       # dt-bind-030
    └── helix.nix         # dt-bind-040
```

### nixos-config Modules (Current)

```
home-manager/common/features/
├── keybindings.nix       # Zellij/Ghostty keybindings (to migrate)
└── cli/
    └── helix.nix         # Helix keybindings (to migrate)
```

## Implementation Details

### 10. Keybindings - Hyprland Navigation (`dt-bind-010`)

* **Module Path**: `home/hyprland/bindings.nix`
* **Technology**: Hyprland
* **Functionality**: Implements J/K/I/L home row navigation pattern for window focus

### 11. Keybindings - Zellij Tab Navigation (`dt-bind-020`)

* **Module Path**: `terminal/zellij.nix` (or nixos-config keybindings.nix)
* **Technology**: Zellij, Nix
* **Functionality**: Configures Ctrl+PgUp/PgDn and Ctrl+Tab for tab navigation, plus future Alt+W/E/R/C pattern

### 12. Keybindings - Zellij Pane Navigation (`dt-bind-021`)

* **Module Path**: `terminal/zellij.nix`
* **Technology**: Zellij
* **Functionality**: Configures Alt+h/j/k/l for directional pane focus without mode switching

### 13. Keybindings - Zellij Mode Remapping (`dt-bind-022`)

* **Module Path**: `terminal/zellij.nix` (or nixos-config keybindings.nix)
* **Technology**: Zellij
* **Functionality**: Remaps Ctrl+G/O to Ctrl+Shift+G/O to avoid Claude Code/Lazygit conflicts

### 14. Keybindings - Ghostty Integration (`dt-bind-030`)

* **Module Path**: `terminal/ghostty.nix` (or nixos-config keybindings.nix)
* **Technology**: Ghostty
* **Functionality**: Unbinds tab/split shortcuts to delegate all multiplexing to Zellij

### 15. Keybindings - Hardware Portability (`dt-bind-060`)

* **Module Path**: `home/hyprland/input.nix`
* **Technology**: XKB, Hyprland
* **Functionality**: Configures altwin:swap_alt_win for consistent keyboard behavior across hardware

## Proposed Changes Summary

### High Priority (Phase 2-3)
1. Add `altwin:swap_alt_win` to Keystone input.nix
2. Change Hyprland navigation to J/K/I/L pattern
3. Change close window to Super+Q
4. Add Alt+h/j/k/l pane navigation to Zellij

### Medium Priority (Phase 4-5)
5. Enhance Helix keybindings
6. Configure browser/Vimium

### Low Priority (Phase 6-7)
7. Hardware documentation
8. Testing and refinement
