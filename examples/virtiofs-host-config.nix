# Example NixOS host configuration with virtiofs support for libvirt
#
# This configuration enables virtiofs filesystem sharing, allowing libvirt VMs
# to mount the host's /nix/store for improved performance during development.
#
# Usage:
#   1. Copy relevant sections to your /etc/nixos/configuration.nix
#   2. Adjust paths to match your setup
#   3. Run: sudo nixos-rebuild switch
#   4. Create VMs with: ./bin/virtual-machine --enable-virtiofs --start

{ config, pkgs, ... }:

{
  # Import the virtiofs host module
  imports = [
    ./path/to/keystone/modules/virtualization/host-virtiofs.nix
  ];

  # Enable virtiofs support for libvirt
  keystone.virtualization.host.virtiofs.enable = true;

  # Ensure your user is in the libvirtd group
  users.users.yourusername = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "libvirtd"
    ];
  };

  # Optional: Additional libvirt configuration
  virtualisation.libvirtd = {
    # Already enabled by the virtiofs module, but you can override:
    # qemu.runAsRoot = false;  # Run QEMU as unprivileged user
    # onBoot = "ignore";  # Don't auto-start VMs on host boot
    # onShutdown = "shutdown";  # Gracefully shutdown VMs on host shutdown
  };

  # Optional: Enable virt-manager for graphical VM management
  programs.virt-manager.enable = true;

  # Optional: Enable remote-viewer for VM display
  environment.systemPackages = with pkgs; [
    virt-viewer # Includes remote-viewer
    virtiofsd # Verify virtiofsd is available
  ];
}
