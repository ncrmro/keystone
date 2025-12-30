# Common ISO configuration (shared between x86_64 and Apple Silicon)
{
  config,
  pkgs,
  lib,
  sshKeys ? [],
  enableTui ? true,
  ...
}: let
  keystone-installer-ui = pkgs.callPackage ../packages/keystone-installer-ui {};
in {
  # Enable SSH daemon for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
    # Start SSH as early as possible
    extraConfig = ''
      UseDNS no
    '';
  };

  # Configure root user with SSH keys
  users.users.root = {
    openssh.authorizedKeys.keys = sshKeys;
    # Explicitly set shell to bash to ensure it works
    shell = pkgs.bashInteractive;
  };

  # Enable networking via NetworkManager (for TUI installer network detection)
  networking = {
    wireless.enable = false;
    networkmanager.enable = true;
  };

  # Include TUI installer and common tools
  environment.systemPackages = with pkgs; [
    keystone-installer-ui
    git
    curl
    wget
    vim
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
    # Secure Boot key management
    sbctl
    # Essential shell tools (explicitly added to be safe)
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
  ];

  # Ensure getty is available on tty1, but only if TUI is disabled
  # When TUI is enabled, it takes over tty1. The conflict resolution in systemd
  # is cleaner if we just don't enable the competing services.
  systemd.services."getty@tty1".enable = !enableTui;
  systemd.services."autovt@tty1".enable = !enableTui;

  # Keystone TUI installer service - auto-starts on boot (when enabled)
  systemd.services.keystone-installer = lib.mkIf enableTui {
    description = "Keystone Installer TUI";
    after = ["network.target" "NetworkManager.service"];
    wants = ["NetworkManager.service"];
    wantedBy = ["multi-user.target"];
    conflicts = ["getty@tty1.service" "autovt@tty1.service"];

    path = with pkgs; [
      networkmanager
      iproute2
      util-linux
      jq
      parted
      cryptsetup
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
      ExecStart = "${keystone-installer-ui}/bin/keystone-installer";
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
  boot.kernelParams = ["console=ttyS0,115200" "console=tty1"];

  # Ensure SSH starts on boot
  systemd.services.sshd.wantedBy = lib.mkForce ["multi-user.target"];

  # Enable flakes - required for installation
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Optimize for installation - less bloat
  documentation.enable = false;
  documentation.nixos.enable = false;

  # Set the ISO label
  image.fileName = lib.mkForce "keystone-installer.iso";
  isoImage.volumeID = lib.mkDefault "KEYSTONE";

  # Include the keystone modules in the ISO for reference
  environment.etc."keystone-modules".source = ../modules;
}
