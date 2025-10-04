{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.client.desktop.greetd;
in
{
  options.keystone.client.desktop.greetd = {
    enable = mkEnableOption "greetd login manager with Hyprland";
  };

  config = mkIf cfg.enable {
    # Enable greetd login manager
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd 'uwsm start -S -F Hyprland'";
        };
      };
    };

    # Ensure greetd user can access video group for display
    users.groups.greetd = { };
    users.users.greeter = {
      isSystemUser = true;
      group = "greetd";
      extraGroups = [ "video" ];
    };

    # Enable required packages
    environment.systemPackages = with pkgs; [
      greetd.tuigreet
    ];
  };
}
