{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.client.desktop.greetd;
in {
  options.keystone.client.desktop.greetd = {
    enable =
      mkEnableOption "greetd login manager with Hyprland"
      // {
        default = true;
      };
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

    # Ensure greeter user can access video group for display
    users.users.greeter.extraGroups = ["video"];

    # Enable required packages
    environment.systemPackages = with pkgs; [
      greetd.tuigreet
    ];
  };
}
