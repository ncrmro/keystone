{
  lib,
  config,
  pkgs,
  omarchy,
  ...
}:
with lib; {
  # Client configuration module
  # Provides interactive workstation/laptop setup with Hyprland desktop

  imports = [
    ../disko-single-disk-root
    ../ssh
    ./desktop/hyprland.nix
    ./desktop/audio.nix
    ./desktop/greetd.nix
    ./desktop/packages.nix
    ./services/networking.nix
    ./services/system.nix
    ./home
  ];

  options.keystone.client = {
    enable =
      mkEnableOption "Keystone client configuration"
      // {
        default = true;
      };
  };

  config = mkIf config.keystone.client.enable {
    # Client-optimized kernel settings
    boot.kernel.sysctl = {
      "vm.swappiness" = 60; # More swap usage acceptable on clients
    };

    # Locale and timezone configuration (user configurable)
    time.timeZone = lib.mkDefault "UTC";
    i18n.defaultLocale = "en_US.UTF-8";

    # Enable mutable users for desktop usage
    users.mutableUsers = true;

    # Additional client-specific packages
    environment.systemPackages = with pkgs; [
      # Web browser
      firefox

      # Development tools
      vscode

      # Media
      vlc
    ];
  };
}
