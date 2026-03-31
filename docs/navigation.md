---
title: Navigation
description: Keyboard-first navigation across Keystone Desktop, Ghostty, Zellij, and project sessions
---

# Navigation

Keystone is designed around keyboard-first navigation across the desktop and the terminal.

Use this page as the single reference for the most important movement and switching keybindings.

## Desktop navigation

These keybindings move you around the desktop, launchers, and workspaces:

- `$mod+Return`: Open Ghostty
- `$mod+Space`: Open Walker
- `$mod+D`: Open the Keystone project switcher
- `$mod+Escape`: Open the Keystone menu
- `$mod+K`: Open the keybindings menu
- `$mod+H` and `$mod+L`: Move focus horizontally
- `$mod+left/right/up/down`: Move focus between windows
- `$mod+Shift+left/right/up/down`: Swap windows
- `$mod+1` through `$mod+0`: Switch workspaces
- `$mod+Shift+1` through `$mod+Shift+0`: Move the current window to a workspace
- `$mod+Tab` and `$mod+Shift+Tab`: Move between workspaces
- `Alt+Tab`: Cycle through windows

Walker prefixes:

- `.`: Files
- `=`: Calculator
- `$`: Clipboard history
- `/`: Provider list

## Terminal navigation

Inside Ghostty and Zellij, these bindings handle tab and session movement:

- `Ctrl+PageUp` / `Ctrl+PageDown`: Previous and next Zellij tab
- `Ctrl+,` / `Ctrl+.`: Previous and next Zellij tab
- `Ctrl+<` / `Ctrl+>`: Move the current Zellij tab left or right
- `Ctrl+T`: Create a new Zellij tab and name it immediately
- `Ctrl+W`: Close the current Zellij tab
- `Ctrl+P`, then arrow keys: Switch panes in Zellij pane mode
- `Ctrl+P`, then `n`: Create a new pane
- `Ctrl+O`, then `d`: Detach from the current Zellij session

Ghostty is configured to stay out of the way for `Ctrl+PageUp` and `Ctrl+PageDown` so Zellij can handle tab switching directly.

## Project and session navigation

Keystone uses project-aware navigation across Walker, `pz`, Ghostty, and Zellij:

- Use `$mod+D` to jump into the project switcher from the desktop
- Use `pz list` to inspect known projects from the terminal
- Use `pz <project>` to open or attach to that project's Zellij session
- Use `zellij attach` to resume an existing session directly

The intended flow is:

1. Jump to a project from the desktop or terminal.
2. Work inside Ghostty with Zellij tabs and panes.
3. Detach instead of closing the session when you are done for now.

## Related docs

- [Desktop keybindings](desktop/keybindings.md)
- [Walker](desktop/walker.md)
- [Terminal module overview](terminal/terminal.md)
- [Developer workflow](terminal/tui-developer-workflow.md)
- [Projects and pz](terminal/projects.md)
