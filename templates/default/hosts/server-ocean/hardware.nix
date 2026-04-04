let
  system = "x86_64-linux"; # TODO: Change if this server uses a different architecture
in
{
  inherit system;

  module =
    {
      config,
      lib,
      modulesPath,
      ...
    }:
    {
      # ============================================================================
      # SERVER HARDWARE CONFIGURATION
      # ============================================================================
      #
      # This host can represent either a VPS or a baremetal server.
      #
      # For VPS deployments, keep only the modules and settings that match your
      # provider's virtual hardware.
      #
      # For baremetal deployments:
      # 1. Boot from the Keystone installer on the target host
      # 2. Run: nixos-generate-config --show-hardware-config
      # 3. Replace this file with the generated output and then reapply the storage
      #    facts below

      imports = [
        # QEMU/KVM guest support is a reasonable default for many VPS environments.
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      # Required for ZFS - unique 8-character hex string
      networking.hostId = "00000000"; # TODO: Generate and replace this value

      # Root disk(s) for the server host.
      keystone.os.storage.devices = [
        "/dev/disk/by-id/YOUR-SERVER-DISK-ID-HERE" # TODO: Replace with your disk ID
      ];

      # Set to "stripe", "mirror", or a raidz mode for multi-disk server roots.
      keystone.os.storage.mode = "single";

      # Remote unlock is commonly needed on headless servers. Set the NIC driver
      # here if you enable keystone.os.remoteUnlock in the host config.
      # keystone.os.remoteUnlock.networkModule = "virtio_net";

      boot.initrd.availableKernelModules = [
        "ahci"
        "nvme"
        "sd_mod"
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_net"
      ];

      boot.kernelModules = [
        "kvm-intel"
        # "kvm-amd"
      ];

      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      hardware.enableRedistributableFirmware = true;
    };
}
