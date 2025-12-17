# Research: Hyprland Desktop Module

## 1. Module Structure and Integration

- **Decision**: The feature will be split into two main modules:
    1.  A NixOS module located at `modules/client/desktop/hyprland.nix`.
    2.  A home-manager module located at `home-manager/modules/desktop/hyprland/default.nix`.
- **Rationale**: This separation aligns with the project's modular architecture, cleanly separating system-wide concerns (like the login manager) from user-specific configurations (like the status bar and wallpaper).
- **Integration**: The NixOS module will handle the `greetd` setup to launch `uwsm`, while the home-manager module will manage the user's desktop applications and configuration files. This follows standard Nix patterns.

## 2. Login Manager: greetd + UWSM

- **Decision**: Use the `services.greetd` option in the NixOS module to configure `greetd` with `tuigreet`. The command launched by `greetd` will be `uwsm`.
- **Rationale**: The user explicitly requested `greetd` and `uwsm`. `greetd` is a flexible and minimal display manager suitable for this environment. `uwsm` (Universal Wayland Session Manager) provides a standard way to launch and manage the Hyprland session and its components.
- **Reference**: The configuration will be similar to standard `greetd` setups in NixOS, adapted to launch `uwsm`. The provided external GitHub link was inaccessible, so implementation will rely on established NixOS practices.

## 3. Core Desktop Components

- **Decision**: The home-manager module will manage the configuration for `waybar`, `mako`, `hyprpaper`, `hyprlock`, and `hypridle`.
- **Rationale**: These components are user-specific and should be configured within the user's home directory. Home-manager is the correct tool for managing these dotfiles and services.
- **Implementation**: Each component will have its own configuration file (e.g., `waybar.nix`, `mako.nix`) imported by the main `hyprland/default.nix` home-manager module to maintain modularity.

## 4. Integration with `terminal-dev-environment`

- **Decision**: The new Hyprland home-manager module will not directly depend on or modify the `terminal-dev-environment` module.
- **Rationale**: The `terminal-dev-environment` module handles terminal-specific tools (`zsh`, `neovim`, etc.). The Hyprland session will launch a terminal (`ghostty`), which will then automatically use the configuration provided by the existing terminal module. This avoids tight coupling and allows both modules to function independently.
