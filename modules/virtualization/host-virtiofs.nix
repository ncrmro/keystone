# Host configuration for virtiofs support in libvirt VMs
#
# This module enables the virtiofsd daemon needed for sharing host filesystems
# with libvirt guests using the virtiofs protocol.
#
# Usage:
#   In your NixOS configuration.nix:
#
#   imports = [ ./modules/virtualization/host-virtiofs.nix ];
#
#   keystone.virtualization.host.virtiofs.enable = true;
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.virtualization.host.virtiofs;
in
{
  options.keystone.virtualization.host.virtiofs = {
    enable = mkEnableOption "virtiofs support for libvirt";
  };

  config = mkIf cfg.enable {
    # Ensure libvirtd is enabled
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = mkDefault true;
        swtpm.enable = mkDefault true;
        # Critical: This lets libvirt find the virtiofsd binary
        vhostUserPackages = [ pkgs.virtiofsd ];
      };
    };
  };
}
