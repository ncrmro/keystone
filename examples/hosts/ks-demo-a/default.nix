# Minimal vm-realized demo host. Real fleets replace this with keystone
# module imports; the harness only requires a bootable NixOS module.
{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.grub.device = "nodev";

  services.openssh.enable = true;
  # Demo-only console access; fleets provision real keys for smoke checks.
  users.users.root.initialPassword = "demo";

  system.stateVersion = "25.05";
}
