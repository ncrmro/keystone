{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  # ============================================================================
  # HARDWARE CONFIGURATION
  # ============================================================================
  #
  # This file contains hardware-specific settings. For real deployments:
  #
  # 1. Boot from the Keystone installer on your target machine
  # 2. Run: nixos-generate-config --show-hardware-config
  # 3. Replace this file's contents with the generated output
  #
  # The configuration below works for QEMU/KVM virtual machines and provides
  # sensible defaults for testing.
  #

  imports = [
    # QEMU/KVM guest support (remove for physical hardware)
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # ──────────────────────────────────────────────────────────────────────────
  # Boot Configuration
  # ──────────────────────────────────────────────────────────────────────────

  # Kernel modules available in initrd
  boot.initrd.availableKernelModules = [
    # Storage controllers
    "ahci" # SATA
    "nvme" # NVMe SSDs
    "sd_mod" # SCSI disks
    "sr_mod" # CD/DVD drives
    "usb_storage" # USB storage

    # USB controllers
    "xhci_pci" # USB 3.0
    "ehci_pci" # USB 2.0
    "usbhid" # USB HID devices

    # Virtualization (QEMU/KVM)
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
  ];

  # Kernel modules to load at boot
  boot.kernelModules = [
    # Virtualization support
    # Uncomment ONE based on your CPU:
    "kvm-intel" # For Intel CPUs
    # "kvm-amd"   # For AMD CPUs
  ];

  # ──────────────────────────────────────────────────────────────────────────
  # CPU Microcode
  # ──────────────────────────────────────────────────────────────────────────
  #
  # Enable microcode updates for security patches.
  # Uncomment the appropriate line for your CPU:

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Enable redistributable firmware (required for most hardware)
  hardware.enableRedistributableFirmware = true;

  # ──────────────────────────────────────────────────────────────────────────
  # Graphics (Optional - uncomment for desktop systems)
  # ──────────────────────────────────────────────────────────────────────────

  # Intel integrated graphics
  # hardware.graphics.enable = true;

  # NVIDIA (proprietary drivers)
  # hardware.nvidia = {
  #   modesetting.enable = true;
  #   open = false;  # Use proprietary driver
  #   nvidiaSettings = true;
  # };
  # services.xserver.videoDrivers = [ "nvidia" ];

  # AMD graphics
  # hardware.graphics.enable = true;
  # services.xserver.videoDrivers = [ "amdgpu" ];

  # ──────────────────────────────────────────────────────────────────────────
  # Laptop Power Management (Optional)
  # ──────────────────────────────────────────────────────────────────────────

  # Enable power management for laptops
  # services.tlp.enable = true;

  # Enable thermald for Intel CPUs
  # services.thermald.enable = true;

  # ──────────────────────────────────────────────────────────────────────────
  # Serial Console (Optional - for headless servers)
  # ──────────────────────────────────────────────────────────────────────────

  # Enable serial console output (useful for VMs and headless servers)
  # boot.kernelParams = [
  #   "console=ttyS0,115200n8"  # Serial console
  #   "console=tty0"            # VGA console as fallback
  # ];
}
