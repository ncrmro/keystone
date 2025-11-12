{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Minimal NixOS configuration for CI testing
  # Simple deployment without Secure Boot, TPM, or encryption
  
  system.stateVersion = "25.05";
  
  # System identity
  networking.hostName = "ci-test-vm";
  
  # Basic boot loader (no Secure Boot)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Simple disk layout - let disko handle partitioning
  disko.devices = {
    disk = {
      main = {
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
  
  # Basic SSH access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  
  # SSH key for deployment - will be overridden by nixos-anywhere
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholder ci-test"
  ];
  
  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    git
  ];
  
  # Enable networking
  networking.useDHCP = true;
  networking.firewall.enable = false; # Simplify for testing
}
