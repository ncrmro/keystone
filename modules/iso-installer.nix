# ISO installer configuration with TUI installer
#
# Provides ISO-specific config layered on top of keystone.os (which handles
# SSH, firewall, flakes, locale) and keystone.terminal (helix, zsh, starship).
#
# This module adds:
# - Root SSH login override (keystone.os defaults to prohibit-password)
# - TUI installer (keystone-tui) auto-starting on tty1
# - ZFS, Secure Boot, TPM, and disko tooling pre-installed
# - NetworkManager for TUI installer network detection
#
# Usage:
#   keystone.installer.sshKeys = [ "ssh-ed25519 AAAAC3..." ];
{
  config,
  pkgs,
  lib,
  ...
}:
let
  keystone-tui = pkgs.callPackage ../packages/keystone-tui { };
in
{
  options.keystone.installer.sshKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "SSH public keys for root access on the installer ISO";
  };

  config = {
    # Enable SSH daemon for remote access
    # mkForce overrides keystone.os.ssh's "prohibit-password" — the installer
    # needs key-based root login for remote installation workflows
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkForce "yes";
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
      };
      extraConfig = ''
        UseDNS no
      '';
    };

    # Configure root user with SSH keys
    users.users.root = {
      openssh.authorizedKeys.keys = config.keystone.installer.sshKeys;
    };

    # Enable networking via NetworkManager (for TUI installer network detection)
    # mkForce needed — installation-cd-minimal.nix enables wpa_supplicant which
    # conflicts with NetworkManager's own wireless management
    networking = {
      wireless.enable = lib.mkForce false;
    };

    # Include TUI installer and tools for installation
    environment.systemPackages = with pkgs; [
      keystone-tui
      git
      curl
      wget
      htop
      lsof
      rsync
      jq
      # Tools needed for installation
      parted
      cryptsetup
      util-linux
      dosfstools
      e2fsprogs
      nix
      nixos-install-tools
      disko
      shadow
      iproute2
      networkmanager
      tpm2-tools
      # ZFS utilities — use the same package boot.supportedFilesystems selects
      config.boot.zfs.package
      # Secure Boot key management
      sbctl
    ];

    # NetworkManager for network detection (required by TUI installer)
    networking.networkmanager.enable = true;

    # Disable getty on tty1 so TUI installer can use it
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;

    # Keystone TUI installer service - auto-starts on boot
    systemd.services.keystone-installer = {
      description = "Keystone Installer TUI";
      after = [
        "network.target"
        "NetworkManager.service"
      ];
      wants = [ "NetworkManager.service" ];
      wantedBy = [ "multi-user.target" ];
      conflicts = [
        "getty@tty1.service"
        "autovt@tty1.service"
      ];

      path = with pkgs; [
        networkmanager
        iproute2
        util-linux
        jq
        tpm2-tools
        parted
        cryptsetup
        config.boot.zfs.package
        dosfstools
        e2fsprogs
        nix
        nixos-install-tools
        disko
        git
        shadow
      ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        ExecStart = "${keystone-tui}/bin/keystone-tui";
        Restart = "on-failure";
        RestartSec = "5s";
        StandardInput = "tty";
        StandardOutput = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = "yes";
        TTYVHangup = "yes";
      };
    };

    # Enable console on both serial (for remote) and tty1 (for TUI installer)
    boot.kernelParams = [
      "console=ttyS0,115200"
      "console=tty1"
    ];

    # Ensure SSH starts on boot
    systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

    # Note: kernel is set in flake.nix to override minimal CD default

    # Enable ZFS for nixos-anywhere deployments
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;

    # ZFS kernel modules — boot.supportedFilesystems handles extraModulePackages,
    # udev, and systemd integration. Only need to ensure the module is loaded.
    boot.kernelModules = [ "zfs" ];

    # Set required hostId for ZFS
    networking.hostId = lib.mkDefault "8425e349";

    # Optimize for installation - less bloat
    documentation.enable = false;
    documentation.nixos.enable = false;

    # Set the ISO label
    image.fileName = lib.mkForce "keystone-installer.iso";
    isoImage.volumeID = lib.mkForce "KEYSTONE";

    # Include the keystone modules in the ISO for reference
    environment.etc."keystone-modules".source = ../modules;
  }; # close config
}
