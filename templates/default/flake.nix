{
  description = "Your Name Keystone System Configuration"; # TODO: Change to your name

  inputs = {
    # By default this template only pins Keystone and reuses Keystone's pinned
    # `nixpkgs`. If you want the more standard flake pattern instead, add your
    # own top-level `nixpkgs` input and uncomment `keystone.inputs.nixpkgs.follows`
    # below so Keystone follows that shared pin.
    #
    # You can override other Keystone inputs the same way. Common examples:
    # - `llm-agents` for AI CLI/tooling versions:
    #   `keystone.inputs.llm-agents.follows = "llm-agents";`
    # - `browser-previews` for Chrome/browser preview builds used by Keystone's
    #   browser tooling:
    #   `keystone.inputs.browser-previews.follows = "browser-previews";`
    #
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # llm-agents.url = "github:numtide/llm-agents.nix";
    # browser-previews.url = "github:nix-community/browser-previews";
    keystone = {
      url = "github:ncrmro/keystone";
      # inputs.nixpkgs.follows = "nixpkgs";
      # inputs.llm-agents.follows = "llm-agents";
      # inputs.browser-previews.follows = "browser-previews";
    };
  };

  outputs =
    {
      keystone,
      ...
    }:
    keystone.lib.mkSystemFlake {
      admin = {
        username = "keystone"; # TODO: Change to your login username
        fullName = "Your Name"; # TODO: Change to your full name
        email = "admin@example.com"; # TODO: Change to your email
        initialPassword = "changeme";
        sshKeys = [ ]; # TODO: Add SSH public keys for remote access
      };
      defaults = {
        timeZone = "UTC"; # TODO: Set your default timezone
      };
      hostsRoot = ./hosts;
      shared = {
        # Home Manager user packages — installed per-user on every host.
        # Start here for tools that should follow your login environment.
        userModules = [
          (
            { pkgs, ... }:
            {
              home.packages = with pkgs; [
                # fd
              ];
            }
          )
        ];

        # NixOS system modules — OS-wide on every host. Use only when something
        # truly belongs at the system level (root-owned packages, services,
        # packages needed for other users).
        systemModules = [
          (
            { pkgs, ... }:
            {
              environment.systemPackages = with pkgs; [
                # btop
              ];
            }
          )
        ];

        # Home Manager desktop packages — per-user on laptop and workstation
        # hosts only, not servers. Use for GUI apps.
        # desktopUserModules = [
        #   (
        #     { pkgs, ... }:
        #     {
        #       home.packages = with pkgs; [
        #         obsidian
        #         vscode
        #         bitwarden-desktop
        #       ];
        #     }
        #   )
        # ];
      };
      keystoneServices = {
        # Shared infrastructure services are placed globally here.
        #
        # Keystone validates that each `*.host` matches a host declared below,
        # then the matching machine auto-enables the corresponding service.
        #
        # Examples:
        # git.host = "server-ocean";
        # mail.host = "server-ocean";
      };

      # Each block below represents a single host in this Keystone system.
      #
      # Common host shapes:
      # - laptop
      # - workstation
      # - server
      # - macbook
      hosts = {
        # ----------------------------------------------------------------------
        # Laptop config
        # ----------------------------------------------------------------------
        laptop = {
          kind = "laptop";

          nixosModules = [
            # keystone.nixosModules.server
          ];
        };

        # ----------------------------------------------------------------------
        # Server config
        # ----------------------------------------------------------------------
        server-ocean = {
          kind = "server";
          hostname = "server-ocean"; # Example only. Rename this host to anything you want.
        };

        macbook = {
          kind = "macbook";
        };
      };
    }
    // {
      devShells.x86_64-linux.default = keystone.inputs.nixpkgs.legacyPackages.x86_64-linux.mkShell {
        packages = with keystone.inputs.nixpkgs.legacyPackages.x86_64-linux; [
          nixfmt
          nil
          imagemagick # PPM→PNG conversion for e2e screenshots
          nix-serve # local binary cache for e2e VM installs
        ];
      };
    };
}
