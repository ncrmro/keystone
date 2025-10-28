{ config, pkgs, ... }:
{
  # Minimal Keystone server configuration for VM testing
  # This configuration enables nixos-anywhere deployment to VMs

  # System identity
  networking.hostName = "test-server";
  # Required for ZFS - unique 8-character hex string
  # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.hostId = "deadbeef";

  # Enable Keystone modules
  keystone = {
    # Disk configuration with ZFS and encryption
    disko = {
      enable = true;
      # Disk device - adjust based on your VM:
      # - QEMU/KVM (virtio): /dev/vda
      # - VirtualBox (SATA): /dev/sda
      # - Physical hardware: /dev/disk/by-id/nvme-... or /dev/disk/by-id/ata-...
      device = "/dev/vda";

      # Swap size (default: 8G)
      # Adjust based on disk size: 20GB VM = 8G, larger systems = 16G or 64G
      # swapSize = "16G";
    };

    # Server services (SSH, mDNS, firewall, etc.)
    server.enable = true;
  };

  # SSH access configuration
  # IMPORTANT: Replace with your actual SSH public key(s)
  # You can get your public key with: cat ~/.ssh/id_ed25519.pub
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
  ];

  # Optional: Set timezone (default: UTC from server module)
  # time.timeZone = "America/New_York";

  # Optional: Additional packages
  # environment.systemPackages = with pkgs; [
  #   neovim
  # ];
}
