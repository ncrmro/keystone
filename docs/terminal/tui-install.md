---
title: Installing Keystone TUI
description: How to install the Keystone Terminal UI environment
---

# Installing Keystone TUI

Keystone TUI is a curated terminal environment powered by Nix. It provides a consistent, high-performance developer experience across macOS and Linux.

## Keystone OS Users

If you are using **Keystone OS**, you don't need to do anything! Keystone TUI comes pre-installed and configured out of the box.

## Non-Keystone OS Users (macOS / Linux)

For users on macOS or other Linux distributions (Ubuntu, Fedora, Arch, etc.), you can install Keystone TUI by following these steps.

### 1. Install Nix

First, you need to have the Nix package manager installed.

- **macOS Users:** Follow the [macOS Installation Guide](/docs/os/build-platforms)
- **Linux Users:** Follow the [Ubuntu/Debian Installation Guide](/docs/os/build-platforms) (also applies to most other Linux distros)

### 2. Install Keystone TUI

Once Nix is installed and flakes are enabled, you can run Keystone TUI directly or install it into your profile.

#### Option A: Try it out (Ephemeral Shell)

To launch a shell with all Keystone tools available without permanently installing them:

```bash
nix shell github:ncrmro/keystone#tui
```

This will drop you into a shell with `helix`, `zellij`, `lazygit`, and other tools available.

#### Option B: Install with Home Manager (Recommended)

For a permanent installation that manages your configuration files (dotfiles), we recommend using **Home Manager**.

1.  **Initialize a simplified flake:**

    create a `flake.nix` file in your preferred config directory (e.g., `~/.config/home-manager/flake.nix`):

    ```nix
    {
      description = "My Keystone TUI Configuration";

      inputs = {
        nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
        keystone.url = "github:ncrmro/keystone";
        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";
      };

      outputs = { self, nixpkgs, keystone, home-manager, ... }: {
        homeConfigurations."YOUR_USERNAME" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux; # Or aarch64-darwin for Apple Silicon
          modules = [
            # Import Keystone TUI module
            keystone.homeManagerModules.tui

            {
              home.username = "YOUR_USERNAME";
              home.homeDirectory = "/home/YOUR_USERNAME"; # Or /Users/YOUR_USERNAME on macOS
              home.stateVersion = "23.11";
            }
          ];
        };
      };
    }
    ```

2.  **Apply the configuration:**

    ```bash
    nix run github:nix-community/home-manager/master -- switch --flake .#YOUR_USERNAME
    ```

## Next Steps

Now that you have the tools installed, learn how to use them effectively in our Developer Workflow guide.

- [**Developer Workflow Guide**](tui-developer-workflow.md) - Learn how to use Zellij, Helix, and other tools together.
