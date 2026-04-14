# Post-install applications

After a fresh Keystone laptop install, the desktop ships with core utilities
and Chromium. Additional applications are added in your config flake.

## Where to add packages

| Where | Scope | Example |
|-------|-------|---------|
| `shared.desktopUserModules` | Your user profile on desktop hosts | Obsidian, VS Code, Bitwarden |
| `shared.userModules` | Your user profile on every host | CLI tools (fd, ripgrep) |
| `shared.systemModules` | System-wide on every host | btop, 1Password NixOS module |
| `hosts/<name>/configuration.nix` | One specific host only | GPU-specific tools |

Desktop user modules apply to laptop and workstation hosts but not servers.
GUI apps belong in `desktopUserModules` as home-manager packages — not at the
OS level.

## flake.nix example

```nix
keystone.lib.mkSystemFlake {
  admin = { /* ... */ };
  hostsRoot = ./hosts;

  shared = {
    # Home Manager user packages — installed per-user on every host.
    userModules = [
      ({ pkgs, ... }: { home.packages = with pkgs; [ fd ]; })
    ];

    # NixOS system packages — installed OS-wide on every host.
    systemModules = [
      ({ pkgs, ... }: { environment.systemPackages = with pkgs; [ btop ]; })
    ];

    # Home Manager user packages — per-user on desktop hosts only.
    desktopUserModules = [
      (
        { pkgs, ... }:
        {
          home.packages = with pkgs; [
            # obsidian              # Knowledge management (vaults at ~/notes/)
            # vscode                # VS Code (supports Claude Code extension)
            # zed-editor
            # bitwarden-desktop
          ];
        }
      )
    ];
  };

  hosts = {
    laptop = { kind = "laptop"; };          # gets desktopUserModules
    workstation = { kind = "workstation"; }; # gets desktopUserModules
    server-ocean = { kind = "server"; };     # does not
  };
}
```

## Notes

- **Chromium** ships by default and is bound to `$mod+B`. Override with
  `keystone.desktop.hyprland.browser`.
- **Helix** ships by default via the terminal module with automatic theme
  integration.
- OS-level desktop settings (like `programs._1password-gui.enable`) go in
  per-host `configuration.nix` or `shared.systemModules` if needed everywhere.

## Applying changes

```bash
ks build        # verify it compiles
ks switch       # apply immediately (requires approval)
```
