# ISO installer configuration with TUI installer
#
# Provides ISO-specific config layered on top of keystone.os (which handles
# SSH, firewall, flakes, locale) and keystone.terminal (helix, zsh, starship).
#
# This module adds:
# - Root SSH login override (keystone.os defaults to prohibit-password)
# - TUI installer (keystone-installer-ui) auto-starting on tty1
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
  ks = pkgs.callPackage ../packages/ks { };
  installerCfg = config.keystone.installer;
in
{
  options.keystone.installer = {
    edition = lib.mkOption {
      type = lib.types.str;
      default = "server";
      description = "ISO edition name used in the filename (e.g. server, desktop).";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0";
      description = "Keystone installer version embedded in the ISO filename.";
    };

    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys for root access on the installer ISO";
    };

    tui.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to install and auto-start the Keystone installer TUI on the ISO (experimental).";
    };
  };

  config = {
    # The live installer builds the target system before first boot, so it needs
    # the shared Keystone cache itself; the normal keystone.os cache defaults are
    # not imported into this minimal ISO module stack.
    nix.settings.substituters = lib.mkBefore [ "https://ks-systems.cachix.org" ];
    nix.settings.trusted-public-keys = lib.mkBefore [
      "ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo="
    ];

    # The live installer can still hit legitimate cache misses while realizing
    # the target host closure. The default minimal ISO has no swap, which makes
    # moderate-memory VM installs fragile. Enable zram-backed swap on the live
    # environment so `nixos-install` has some headroom when the cache is cold.
    zramSwap.enable = true;

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
      openssh.authorizedKeys.keys = installerCfg.sshKeys;
    };

    # Disable wpa_supplicant — NetworkManager handles wireless
    networking = {
      wireless.enable = lib.mkForce false;
    };

    # Include TUI installer and tools for installation
    environment.systemPackages = [
      # Provide `ks` in the live installer shell so `ks install` works
      # immediately after boot.
      ks
    ]
    ++ (with pkgs; [
      git
      curl
      wget
      htop
      lsof
      rsync
      jq
      # Tools needed for installation and recovery
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
    ]);

    # installation-cd-minimal enables NetworkManager by default, but in headless
    # VM tests that can leave interfaces unconfigured. Use classic DHCP for the
    # non-TUI path so SSH comes up reliably, and keep NetworkManager for TUI mode.
    networking.networkmanager.enable = lib.mkForce installerCfg.tui.enable;
    networking.useDHCP = lib.mkIf (!installerCfg.tui.enable) (lib.mkForce true);

    # Disable getty on tty1 so the TUI installer can take over the console.
    systemd.services."getty@tty1".enable = lib.mkIf installerCfg.tui.enable false;
    systemd.services."autovt@tty1".enable = lib.mkIf installerCfg.tui.enable false;

    # ks installer service - auto-starts on boot
    systemd.services.keystone-installer = lib.mkIf installerCfg.tui.enable {
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
        # Clear any residual boot output and restore cursor before TUI starts.
        # Uses /bin/sh because systemd ExecStartPre doesn't support shell redirects.
        ExecStartPre = "/bin/sh -c '${pkgs.util-linux}/bin/setterm --clear all --cursor on > /dev/tty1'";
        ExecStart = "${ks}/bin/ks";
        Restart = "on-failure";
        RestartSec = "5s";
        StandardInput = "tty";
        StandardOutput = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = "yes";
        TTYVHangup = "yes";
      };
    };

    # Suppress boot messages so the TUI appears cleanly on tty1.
    # console=tty1 keeps the display signal active (prevents "no signal" flash
    # between GRUB and the TUI); quiet + loglevel=0 ensure nothing is printed.
    # Serial still receives all boot logs for remote debugging.
    boot.consoleLogLevel = lib.mkIf installerCfg.tui.enable 0;
    boot.initrd.verbose = lib.mkIf installerCfg.tui.enable false;
    boot.kernelParams = lib.mkIf installerCfg.tui.enable [
      "console=ttyS0,115200"
      "console=tty1"
      "quiet"
      "loglevel=0"
      "rd.udev.log_level=3"
      "systemd.show_status=false"
      "vt.global_cursor_default=0"
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

    # Set the ISO name, label, and boot splash image
    image.baseName = lib.mkForce "keystone-${installerCfg.edition}-installer-${installerCfg.version}";
    isoImage.volumeID = lib.mkDefault "KEYSTONE";
    isoImage.efiSplashImage = ../assets/installer-splash.png;
    isoImage.splashImage = ../assets/installer-splash.png;
    # Disable the default NixOS GRUB theme so the keystone splash image shows
    isoImage.grubTheme = null;

    # Include the keystone modules in the ISO for reference
    environment.etc."keystone-modules".source = ../modules;
  }; # close config
}
