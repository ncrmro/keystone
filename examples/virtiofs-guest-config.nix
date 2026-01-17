# Example NixOS guest VM configuration with virtiofs support
#
# This configuration mounts the host's /nix/store via virtiofs with an
# overlay filesystem to provide a writable layer.
#
# Prerequisites:
#   - Host must have virtiofs enabled (see virtiofs-host-config.nix)
#   - VM must be created with --enable-virtiofs flag
#
# Usage:
#   1. Create VM: ./bin/virtual-machine --name my-vm --enable-virtiofs --start
#   2. Deploy this config: nixos-anywhere --flake .#my-vm root@192.168.100.99

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Import the virtiofs guest module
  imports = [
    ./path/to/keystone/modules/virtualization/guest-virtiofs.nix
    # Your other imports...
  ];

  # Enable virtiofs filesystem sharing
  keystone.virtualization.guest.virtiofs = {
    enable = true;

    # Must match the <target dir> in VM's libvirt XML
    shareName = "nix-store-share";

    # Use tmpfs for overlay (default - writes lost on reboot)
    persistentRwStore = false;

    # Alternative: Use persistent disk for overlay
    # persistentRwStore = true;
    # Then add a filesystem for /sysroot/nix/.rw-store
  };

  # System configuration
  system.stateVersion = "25.05";
  networking.hostName = "virtiofs-guest-vm";

  # Basic VM settings
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Serial console for debugging
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Example user
  users.users.testuser = {
    isNormalUser = true;
    initialPassword = "test";
    extraGroups = [ "wheel" ];
  };

  # Optional: Verify virtiofs is working at boot
  systemd.services.verify-virtiofs = {
    description = "Verify virtiofs mount is working";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "verify-virtiofs" ''
        echo "Checking virtiofs mount..."
        if mount | grep -q "virtiofs"; then
          echo "✓ virtiofs mount found"
          mount | grep virtiofs
        else
          echo "✗ virtiofs mount NOT found!"
          exit 1
        fi

        echo "Checking overlay mount..."
        if mount | grep -q "overlay on /nix/store"; then
          echo "✓ overlay mount found"
          mount | grep "overlay on /nix/store"
        else
          echo "✗ overlay mount NOT found!"
          exit 1
        fi

        echo "Checking /nix/store access..."
        if [ -d "/nix/store" ] && [ "$(ls /nix/store | wc -l)" -gt 0 ]; then
          echo "✓ /nix/store is accessible and contains $(ls /nix/store | wc -l) paths"
        else
          echo "✗ /nix/store is empty or inaccessible!"
          exit 1
        fi

        echo "✓ virtiofs setup verified successfully"
      '';
    };
  };
}
