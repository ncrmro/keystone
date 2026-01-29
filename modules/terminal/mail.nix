{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
in
{
  options.keystone.terminal.mail = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable mail CLI tools (himalaya)";
    };
  };

  config = mkIf (cfg.enable && cfg.mail.enable) {
    home.packages = [
      # Himalaya - CLI to manage emails
      # https://github.com/pimalaya/himalaya
      # Provided via keystone overlay
      pkgs.keystone.himalaya
    ];
  };
}
