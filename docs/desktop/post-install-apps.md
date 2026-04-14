# Post-install applications

After a fresh Keystone laptop install, the desktop ships with core utilities
(file manager, terminal, media player) and Chromium as the default browser.
Common applications are added in your host's `configuration.nix`.

## Example configuration

This shows all common post-install options in one place. Uncomment what you
need in `hosts/<hostname>/configuration.nix`:

```nix
{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    git
    helix

    ## Browsers — Chromium ships by default, add others here
    # keystone.google-chrome     # Google Chrome (Keystone overlay)
    # firefox

    ## Code editors
    # vscode                     # VS Code (supports Claude Code extension)
    # zed-editor                 # Zed
    # neovim
    # sublime4

    ## Knowledge management
    # obsidian                   # Point vault at ~/notes/ to share with zk

    ## Password managers
    # bitwarden-desktop
    # bitwarden-cli              # CLI for Walker/agent integration
  ];

  ## 1Password — uses NixOS module options instead of systemPackages
  # programs._1password-gui.enable = true;
  # programs._1password.enable = true;   # CLI for scripting and agent integration

  ## To switch the default browser from Chromium to Chrome:
  # keystone.desktop.hyprland.browser =
  #   "uwsm app -- google-chrome-stable --new-window --ozone-platform=wayland";
}
```

## Notes

- **Helix** ships by default via the terminal module with automatic theme
  integration.
- **Chromium** is the default browser bound to `$mod+B`. Override with
  `keystone.desktop.hyprland.browser`.
- **1Password / Bitwarden CLI** can be used from Walker's command runner
  (`$mod+Space`) for quick secret lookups.
- **Obsidian** vaults are local directories — point at `~/notes/` to share
  the same directory as `zk` (the Keystone notes CLI).

## Applying changes

```bash
ks build        # verify it compiles
ks switch       # apply immediately (requires approval)
```
