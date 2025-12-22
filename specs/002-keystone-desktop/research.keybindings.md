# Keystone Desktop - Keybindings Research

This document collects documentation references, hardware specifications, and research materials for the keybindings implementation.

## Documentation References

### Window Manager

- **Hyprland Keybinds**: https://wiki.hypr.land/Configuring/Binds/
- **Current config location**: `~/.config/hypr/hyprland.conf`
- **Keystone module**: `modules/keystone/desktop/home/hyprland/bindings.nix`

### Terminal Emulator

- **Ghostty Keybindings**: https://ghostty.org/docs/config/keybind
- **Action Reference**: https://ghostty.org/docs/config/keybind/reference
- **List defaults**: Run `ghostty +list-keybinds --default`

### Terminal Multiplexer

- **Zellij Keybindings Guide**: https://zellij.dev/documentation/keybindings.html
- **Binding Guide**: https://zellij.dev/documentation/keybindings-binding.html
- **Default Keybindings**: https://github.com/zellij-org/zellij/blob/main/zellij-utils/assets/config/default.kdl

### Text Editor

- **Helix Keymap Docs**: https://docs.helix-editor.com/keymap.html
- **In-editor help**: Run `:help keymap` inside Helix

### Browser Extension

- **Vimium**: https://github.com/philc/vimium
- **Vimium C**: https://github.com/gdh1995/vimium-c

### Hardware

- **UHK Agent**: https://ultimatehackingkeyboard.github.io/agent/

## Hardware-Specific Configurations

### Ultimate Hacking Keyboard (UHK)

**Layer Architecture:**

The UHK uses a layer system where each layer binds actions to keys. Fn2 is positioned under the right thumb for ergonomic access.

**Fn2 Layer (Hyprland Navigation):**
- Position: Right thumb key
- Purpose: Ergonomic access to Hyprland window management
- Mappings are manually configured in UHK Agent (not blanket Alt modifier)

**Mod Layer (Arrow Keys + Tab Navigation):**

Arrow Keys (JKIL):
- `Mod + J` -> Left Arrow
- `Mod + K` -> Down Arrow
- `Mod + I` -> Up Arrow
- `Mod + L` -> Right Arrow

Tab Navigation (WERC):
- `Mod + W` -> `Ctrl + PgUp` (Previous tab)
- `Mod + E` -> `Ctrl + T` (New tab)
- `Mod + R` -> `Ctrl + PgDn` (Next tab)
- `Mod + C` -> `Ctrl + W` (Close tab)

Browser Navigation:
- `Mod + Super + J` -> `Alt + Left Arrow` (Browser back)
- `Mod + Super + L` -> `Alt + Right Arrow` (Browser forward)

**Configuration Method:**
1. Open UHK Agent
2. Select Fn2/Mod layer
3. Click key to configure
4. Set secondary role to: "Keystroke" -> Select modifiers -> Select key
5. Save to keyboard

### Framework Laptop

**Keyboard Layout:**
- No dedicated navigation cluster (Home/End/PgUp/PgDn)
- Function keys require Fn modifier (F1-F12)
- No numpad
- Trackpad available (but prefer keyboard-only workflow)

**PgUp/PgDn Access:**
- `Fn + Arrow Up` = PgUp
- `Fn + Arrow Down` = PgDn

**Tab Navigation:**
- `Fn + Ctrl + Arrow Up` = Ctrl+PgUp (previous tab)
- `Fn + Ctrl + Arrow Down` = Ctrl+PgDn (next tab)
- Alternative: `Ctrl + Shift + Tab` / `Ctrl + Tab`

**Function Row:**
- Media controls: Fn+F1-F12
- Brightness: Fn+F7/F8
- Volume: Fn+F9/F10/F11

### Portable Programmable Keyboard (Future)

**Recommended Options:**
- **Corne (40-42 keys)**: Split, ergonomic, highly portable
- **Planck (47-48 keys)**: Ortholinear, compact, classic
- **Preonic (60 keys)**: Planck with number row
- **Lily58**: Split, more keys than Corne
- **Kyria**: Split, ergonomic, thumb clusters

**Selection Criteria:**
1. QMK/ZMK firmware support (for custom key mappings)
2. Thumb cluster or thumb keys (for layer access)
3. Travel-friendly size (fits in laptop bag)
4. Split or compact ergonomic layout

**Configuration Strategy (QMK/ZMK):**
- Keyboard firmware sends `Alt+JKIL` codes for navigation
- OS-level `altwin:swap_alt_win` swaps to `Super+JKIL`
- Hyprland receives `Super+JKIL` for navigation
- Identical behavior to UHK and Framework

### MacBook

**Important**: MacBook runs macOS, not Hyprland. Hyprland-specific keybindings don't apply.

**Keyboard Layout Differences:**
- **Command** key instead of Super/Win (primary modifier on macOS)
- **Option** key instead of Alt
- Touch Bar on some models

**Window Management on macOS:**
- Native: Mission Control, Spaces
- Alternative tiling WMs: Aerospace, Rectangle, Amethyst, yabai

**Portable Keyboard with macOS:**

Option 1: Configure macOS window manager for Cmd+JKIL
Option 2: Use Karabiner-Elements to swap Option<->Command (matches Linux approach)

**Cross-Platform Tools (same config on macOS):**
- Ghostty
- Zellij
- Helix
- Browser/Vimium
- Git aliases

## Hardware Translation Table

| Action | UHK (NixOS) | Framework (NixOS) | Portable QMK/ZMK (NixOS) | MacBook (macOS) |
|--------|-------------|-------------------|--------------------------|-----------------|
| WM Focus Left | Fn2+J -> Alt+J -> Super+J | Alt+J -> Super+J | Lower+J -> Alt+J -> Super+J | Cmd+J or Option+J |
| WM Focus Down | Fn2+K -> Alt+K -> Super+K | Alt+K -> Super+K | Lower+K -> Alt+K -> Super+K | Cmd+K or Option+K |
| WM Focus Up | Fn2+I -> Alt+I -> Super+I | Alt+I -> Super+I | Lower+I -> Alt+I -> Super+I | Cmd+I or Option+I |
| WM Focus Right | Fn2+L -> Alt+L -> Super+L | Alt+L -> Super+L | Lower+L -> Alt+L -> Super+L | Cmd+L or Option+L |
| Previous Tab | Mod+W -> Ctrl+PgUp | Ctrl+PgUp or Ctrl+Shift+Tab | Mod+W -> Alt+W | Cmd+Shift+[ |
| New Tab | Mod+E -> Ctrl+T | Ctrl+T | Mod+E -> Alt+E | Cmd+T |
| Next Tab | Mod+R -> Ctrl+PgDn | Ctrl+PgDn or Ctrl+Tab | Mod+R -> Alt+R | Cmd+Shift+] |
| Close Tab | Mod+C -> Ctrl+W | Ctrl+W | Mod+C -> Alt+C | Cmd+W |
| Browser Back | Mod+Super+J -> Alt+Left | Alt+Left | Mod+Super+J -> Alt+Left | Cmd+Left |
| Browser Forward | Mod+Super+L -> Alt+Right | Alt+Right | Mod+Super+L -> Alt+Right | Cmd+Right |
| Arrow Keys | Mod+JKIL | Standard arrows | Firmware layer | Standard arrows |

**Key: altwin:swap_alt_win**

On NixOS/Linux, the `altwin:swap_alt_win` XKB option swaps Alt and Super at the input level:
- Physical Alt -> System interprets as Super -> Hyprland receives Super
- This enables ergonomic thumb access to window management

## Reference Materials

### App Groups Spike

Location: `nixos-config/spikes/1757895719_hyprland_app_groups/`

Contains:
- Workspace layout suggestions
- App group launch patterns
- Suggested keybindings for group management

### Related Configuration Files

**In nixos-config:**
- Keybindings module: `home-manager/common/features/keybindings.nix`
- Helix config: `home-manager/common/features/cli/helix.nix`
- Git aliases: `home-manager/common/features/cli/git.nix`
- Input config: `home-manager/common/features/desktop/default.nix`

**In Keystone:**
- Hyprland bindings: `modules/keystone/desktop/home/hyprland/bindings.nix`
- Hyprland input: `modules/keystone/desktop/home/hyprland/input.nix`
- Terminal module: `modules/keystone/terminal/`

## Design Philosophy

### Core Principles

1. **Mouse-Free Workflow**: Eliminate mouse usage for all development workflows
2. **Home Row Optimization**: Minimize finger travel from home row position
3. **Thumb Utilization**: Use ergonomic thumb keys for frequent modifiers
4. **Symmetrical Usage**: Balance left/right hand workload
5. **Layer Coherence**: Related functions grouped on same layer
6. **Reduced Strain**: Avoid awkward Ctrl+Shift+Alt combinations

### Modifier Key Strategy

- **Super**: Hyprland window manager modifier (accessed via physical Alt after swap)
- **Ctrl**: Application-level operations
- **Shift**: Modifications to base keybindings (reverse direction, new window vs current)

### Navigation Patterns

**Spatial Navigation (J/K/I/L):**
- `j` = left, `k` = down, `i` = up, `l` = right
- Stays on home row for maximum ergonomics
- Used consistently across Hyprland, Zellij panes

**Tab Navigation (W/E/R/C):**
- `w` = previous tab, `e` = new tab, `r` = next tab, `c` = close tab
- Mnemonic: W<-E->R (left-to-right on keyboard), C for close
- Used consistently across browser, terminal, and multiplexer

### Portability Strategy

**Hardware-Independent Approach:**
1. OS-level `altwin:swap_alt_win` makes ALL keyboards work identically
2. Keyboard firmware sends Alt codes for window management
3. Single Nix configuration supports all hardware
4. Zero config changes when switching keyboards

**Adding a New Programmable Keyboard:**
1. Flash firmware (UHK Agent, QMK, or ZMK)
2. Configure navigation layer: Fn2/Lower + JKIL -> Alt+JKIL
3. Configure tab layer: Mod + WERC -> Alt+WERC
4. Plug in keyboard - everything works immediately
