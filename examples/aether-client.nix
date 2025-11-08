# Aether Desktop Configuration Example
#
# This configuration demonstrates how to enable Aether theming application
# on a Keystone client system with full desktop environment support.
#
# Usage:
#   Deploy with: nixos-anywhere --flake .#aether-client root@<target-ip>

{ config, pkgs, lib, ... }:

{
  # System Identity
  networking.hostName = "aether-client";

  # Enable Keystone Client with Aether
  keystone.client = {
    enable = true;
    
    desktop = {
      # Core desktop components
      hyprland.enable = true;
      audio.enable = true;
      greetd.enable = true;
      packages.enable = true;
      
      # Aether theming application
      aether.enable = true;
    };

    services = {
      networking.enable = true;
      system.enable = true;
    };

    home = {
      enable = true;
      omarchy.enable = true;
    };
  };

  # Disk Configuration
  keystone.disko = {
    enable = true;
    device = "/dev/disk/by-id/nvme-CHANGEME"; # Change this to your disk
    enableEncryptedSwap = true;
    swapSize = "16G"; # Adjust based on RAM
  };

  # User Configuration
  users.users.user = {
    isNormalUser = true;
    description = "Aether User";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    initialPassword = "changeme"; # Change this after first login
  };

  # Optional: Install hyprshade for shader effects support
  environment.systemPackages = with pkgs; [
    # hyprshade  # Uncomment to enable shader support in Aether
  ];

  # System State Version
  system.stateVersion = "25.05";
}
