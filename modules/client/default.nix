{
  lib,
  config,
  pkgs,
  ...
}:
with lib; {
  # Client configuration module
  # Provides interactive workstation/laptop setup with Hyprland desktop

  imports = [
    ../disko-single-disk-root
    ./desktop/hyprland.nix
    ./desktop/audio.nix
    ./desktop/greetd.nix
    ./desktop/packages.nix
    ./services/networking.nix
    ./services/system.nix
  ];

  options.keystone.client = {
    enable = mkEnableOption "Keystone client configuration" // {default = true;};

    desktop = {
      hyprland.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Hyprland Wayland compositor";
      };

      audio.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable PipeWire audio system";
      };

      greetd.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable greetd login manager";
      };

      packages.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable essential desktop packages";
      };
    };

    services = {
      networking.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable NetworkManager and network services";
      };

      system.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable system services and configuration";
      };
    };
  };

  config = mkIf config.keystone.client.enable {
    # Enable desktop components based on configuration
    keystone.client = {
      desktop = {
        hyprland.enable = mkDefault config.keystone.client.desktop.hyprland.enable;
        audio.enable = mkDefault config.keystone.client.desktop.audio.enable;
        greetd.enable = mkDefault config.keystone.client.desktop.greetd.enable;
        packages.enable = mkDefault config.keystone.client.desktop.packages.enable;
      };

      services = {
        networking.enable = mkDefault config.keystone.client.services.networking.enable;
        system.enable = mkDefault config.keystone.client.services.system.enable;
      };
    };

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
