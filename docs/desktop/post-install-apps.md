# Post-install applications

After a fresh Keystone laptop install, the desktop ships with core utilities
and Chromium. Additional applications are added in your config flake.

## Where to add packages

| Where | Scope | Example |
|-------|-------|---------|
| `shared.desktopUserModules` | Your user profile on desktop hosts | Obsidian |
| `shared.desktopSystemModules` | System-wide on desktop hosts | Chrome, 1Password, VS Code |
| `shared.userModules` | Your user profile on every host | CLI tools |
| `shared.systemModules` | System-wide on every host | btop |
| `hosts/<name>/configuration.nix` | One specific host only | GPU-specific tools |

Desktop modules apply to laptop and workstation hosts but not servers.

## flake.nix example

In your `mkSystemFlake` call:

```nix
keystone.lib.mkSystemFlake {
  admin = { /* ... */ };
  hostsRoot = ./hosts;

  shared = {
    # User-level tools — every host including servers.
    userModules = [
      ({ pkgs, ... }: { home.packages = with pkgs; [ fd ]; })
    ];

    # System-level packages — every host including servers.
    systemModules = [
      ({ pkgs, ... }: { environment.systemPackages = with pkgs; [ btop ]; })
    ];

    # Desktop user tools — laptop and workstation only.
    desktopUserModules = [
      (
        { pkgs, ... }:
        {
          home.packages = with pkgs; [
            # obsidian              # Knowledge management (vaults at ~/notes/)
          ];
        }
      )
    ];

    # Desktop system packages — laptop and workstation only.
    desktopSystemModules = [
      (
        { pkgs, ... }:
        {
          environment.systemPackages = with pkgs; [
            # keystone.google-chrome  # Google Chrome (Keystone overlay)
            # firefox
            # vscode                  # VS Code (supports Claude Code extension)
            # zed-editor
            # bitwarden-desktop
            # bitwarden-cli           # CLI for Walker/agent integration
          ];

          ## 1Password — uses NixOS module options
          # programs._1password-gui.enable = true;
          # programs._1password.enable = true;
        }
      )
    ];
  };

  hosts = {
    laptop = { kind = "laptop"; };       # gets desktop modules
    workstation = { kind = "workstation"; }; # gets desktop modules
    server-ocean = { kind = "server"; };  # does not
  };
}
```

## Notes

- **Chromium** ships by default and is bound to `$mod+B`. Override with
  `keystone.desktop.hyprland.browser`.
- **Helix** ships by default via the terminal module with automatic theme
  integration.
- **1Password / Bitwarden CLI** can be used from Walker's command runner
  (`$mod+Space`) for quick secret lookups.

## Applying changes

```bash
ks build        # verify it compiles
ks switch       # apply immediately (requires approval)
```
