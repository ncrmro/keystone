# Post-install applications

After a fresh Keystone laptop install, the desktop ships with core utilities
and Chromium. Additional applications are added in your config flake.

There are three places to add packages, depending on scope:

| Where | Scope | Example |
|-------|-------|---------|
| `shared.userModules` | Your user profile on every host | CLI tools, Obsidian |
| `shared.systemModules` | System-wide on every host | 1Password, printing |
| `hosts/<name>/configuration.nix` | One specific host only | GPU-specific tools |

## flake.nix — shared modules

In your `mkSystemFlake` call, `shared.userModules` and `shared.systemModules`
apply to all hosts. This is where most post-install apps belong:

```nix
keystone.lib.mkSystemFlake {
  admin = { /* ... */ };
  hostsRoot = ./hosts;

  shared = {
    # User-level tools — follow your login environment on every host.
    userModules = [
      (
        { pkgs, ... }:
        {
          home.packages = with pkgs; [
            fd
            # obsidian              # Knowledge management (vaults at ~/notes/)
          ];
        }
      )
    ];

    # System-level packages — OS-wide on every host (including servers).
    systemModules = [
      (
        { pkgs, ... }:
        {
          environment.systemPackages = with pkgs; [
            # keystone.google-chrome  # Google Chrome (Keystone overlay)
            # firefox
            # vscode                  # VS Code (supports Claude Code extension)
            # zed-editor              # Zed editor
            # bitwarden-desktop
            # bitwarden-cli           # CLI for Walker/agent integration
          ];

          ## 1Password — uses NixOS module options
          # programs._1password-gui.enable = true;
          # programs._1password.enable = true;  # CLI for scripting
        }
      )
    ];
  };

  hosts = {
    laptop = { kind = "laptop"; };
    server-ocean = { kind = "server"; };
  };
}
```

## hosts/laptop/configuration.nix — per-host overrides

For packages that only belong on one machine:

```nix
{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    git
    helix
    # antigravity              # IDE — only on this laptop
    # davinci-resolve          # Video editing — needs GPU
  ];

  # services.printing.enable = true;
}
```

## Notes

- **Chromium** ships by default and is bound to `$mod+B`. Override with
  `keystone.desktop.hyprland.browser`.
- **Helix** ships by default via the terminal module with automatic theme
  integration.
- **`shared.systemModules` applies to all hosts** including servers. There is
  not yet a desktop-only shared module scope — use per-host `configuration.nix`
  for desktop-specific system packages that should not land on servers.

## Applying changes

```bash
ks build        # verify it compiles
ks switch       # apply immediately (requires approval)
```
