# Post-install applications

After a fresh Keystone laptop install, the desktop ships with core utilities
(file manager, terminal, media player) and Chromium as the default browser.
This guide covers how to install and configure common additional applications.

## Browsers

### Chromium (default)

Chromium ships with the Keystone desktop. The `$mod+B` binding opens it.

### Google Chrome

Add to your host configuration:

```nix
environment.systemPackages = [ pkgs.keystone.google-chrome ];
```

To make Chrome the default browser, set the Hyprland option:

```nix
keystone.desktop.hyprland.browser = "uwsm app -- google-chrome-stable --new-window --ozone-platform=wayland";
```

### Firefox

```nix
environment.systemPackages = [ pkgs.firefox ];
```

## Code editors

### VS Code

```nix
environment.systemPackages = [ pkgs.vscode ];
```

VS Code integrates with Claude Code via the VS Code extension. After install,
open the command palette and search "Claude Code" to configure.

### Helix (terminal, ships by default)

Helix is included in the Keystone terminal module. Theme integration is
automatic via `keystone.desktop.theme`.

### Other editors

```nix
# Zed
environment.systemPackages = [ pkgs.zed-editor ];

# Neovim
environment.systemPackages = [ pkgs.neovim ];

# Sublime Text
environment.systemPackages = [ pkgs.sublime4 ];
```

## Knowledge management

### Obsidian

```nix
environment.systemPackages = [ pkgs.obsidian ];
```

Obsidian stores vaults as local directories. Point it at `~/notes/` to use the
same directory as `zk` (the Keystone notes CLI).

## Password managers

### 1Password

```nix
# GUI application
programs._1password-gui.enable = true;
# CLI (for scripting and agent integration)
programs._1password.enable = true;
```

#### Walker integration

1Password CLI (`op`) can be used from Walker's command runner. Press
`$mod+Space`, type a command like `op item get "GitHub" --fields password`, and
the output appears in Walker's preview pane.

### Bitwarden

```nix
environment.systemPackages = with pkgs; [
  bitwarden-desktop  # GUI
  bitwarden-cli      # CLI
];
```

#### Walker integration

After `bw login` and `bw unlock`, use Walker's command runner to query items:
`bw get password github.com`. For persistent unlock, export `BW_SESSION` in
your shell profile.

## Antigravity IDE

Antigravity is a standalone IDE. Add to your configuration:

```nix
environment.systemPackages = [ pkgs.antigravity ];
```

## Applying changes

After editing your host `configuration.nix`, rebuild:

```bash
ks build        # verify it compiles
ks switch       # apply immediately (requires approval)
```

Or use the full update cycle:

```bash
ks update       # pull, lock, build, push, deploy
```
