# Demo host with a machine realization (see targets in flake.nix) — the
# ks-test-delltop pattern: deployable to real hardware by default, still
# bootable as a VM with `ks-fleet test ks-demo-b --as vm`.
{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.grub.device = "nodev";

  services.openssh.enable = true;
  users.users.root.initialPassword = "demo";

  system.stateVersion = "25.05";
}
