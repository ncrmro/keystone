{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  # Minimal Keystone configuration for Kodi GBM kiosk testing.
  # Uses nixos-rebuild build-vm for fast iteration without encryption/secure boot.
  #
  # Build with: nixos-rebuild build-vm --flake ./tests#build-vm-kodi
  # Run with:   ./result/bin/run-keystone-buildvm-kodi-vm
  #
  # Imports only modules/os/kodi.nix (self-contained) — no full keystone.os, so
  # no disko/storage/secure-boot machinery is pulled in.

  imports = [
    # virtio driver stack (incl. virtio_gpu) + guest agent. Required for VM graphics.
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/os/kodi.nix
  ];

  system.stateVersion = "25.05";
  networking.hostName = "keystone-buildvm-kodi";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
    "virtio_scsi"
    "sr_mod"
  ];

  # The kiosk under test.
  keystone.os.services.kodi.enable = true;

  # Kodi needs an audio server (the module deliberately doesn't pick one).
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # GL-capable virtio-gpu so kodi-gbm gets accelerated GLES (virgl) instead of
  # llvmpipe. gl=on requires the *host* to have working OpenGL. Scoped to the
  # build-vm variant — virtualisation.qemu.* only exists in the qemu-vm config.
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-device virtio-vga-gl"
    "-display gtk,gl=on"
  ];

  # Serial console for headless debugging (journalctl over ttyS0), plus tty0 for
  # the kodi VT. Kodi takes tty1; logs land in the journal (StandardOutput=journal).
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  networking.useDHCP = lib.mkDefault true;

  users.mutableUsers = true;
  users.users.root.initialPassword = "root";
  users.users.testuser = {
    isNormalUser = true;
    description = "Kodi VM test user";
    initialPassword = "testpass"; # test only — insecure
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
