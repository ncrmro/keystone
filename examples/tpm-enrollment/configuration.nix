# Example: TPM Enrollment Configuration
#
# This example shows how to enable TPM enrollment for automatic disk unlock
# on a Keystone system.
#
# Usage:
#   1. Deploy this configuration with nixos-anywhere
#   2. Boot the system and log in
#   3. Run: sudo keystone-enroll-recovery
#   4. Save the recovery key securely
#   5. Reboot to test automatic TPM unlock
{
  config,
  pkgs,
  lib,
  ...
}: {
  # Import required Keystone modules
  imports = [
    # These would be imported from the Keystone flake in a real deployment:
    # keystone.nixosModules.diskoSingleDiskRoot
    # keystone.nixosModules.secureBoot
    # keystone.nixosModules.tpmEnrollment
  ];

  # Basic system configuration
  networking.hostName = "keystone-example";
  networking.hostId = "12345678"; # Required for ZFS

  # Enable Keystone disk encryption with disko
  keystone.disko = {
    enable = true;
    device = "/dev/vda"; # Or /dev/disk/by-id/... for bare metal
    swapSize = "8G";
  };

  # Enable Secure Boot (prerequisite for TPM enrollment)
  keystone.secureBoot = {
    enable = true;
  };

  # Enable TPM enrollment module with default settings
  keystone.tpmEnrollment = {
    enable = true;

    # Optional: Customize PCR list
    # Default [1 7] is recommended for most users
    # tpmPCRs = [ 1 7 ];  # Default: Firmware config + Secure Boot
    # tpmPCRs = [ 7 ];    # More update-resilient: Secure Boot only
    # tpmPCRs = [ 0 1 7 ]; # More restrictive: Firmware code + config + Secure Boot

    # Optional: Custom credstore device (if you modified disko config)
    # credstoreDevice = "/dev/zvol/rpool/credstore";  # Default
  };

  # User account configuration
  users.users.root = {
    # Allow SSH with password for initial setup (disable after enrollment)
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... your-key-here"
    ];
  };

  # Enable SSH for remote management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # Change to "prohibit-password" after setup
      PasswordAuthentication = true; # Disable after SSH key setup
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    tmux
  ];

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
