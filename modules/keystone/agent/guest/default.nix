{
  config,
  lib,
  pkgs,
  ...
}: {
  # Guest OS Configuration
  # This module is used inside the MicroVM sandbox environment
  
  imports = [
    ./agents.nix
    ./tools.nix
    ./zellij.nix
    ./worktree.nix
  ];

  # Basic system configuration for guest
  system.stateVersion = "25.05";

  # Minimal user configuration
  users.users.sandbox = {
    isNormalUser = true;
    description = "Sandbox User";
    extraGroups = ["wheel"];
    initialPassword = "sandbox";
  };

  # Enable sudo without password for convenience in sandbox
  security.sudo.wheelNeedsPassword = false;

  # Networking
  networking = {
    hostName = "agent-sandbox";
    firewall.enable = true;
  };

  # Essential packages
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    htop
    tree
  ];
}
