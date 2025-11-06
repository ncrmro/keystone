{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
in
{
  config = lib.mkIf (cfg.enable && cfg.tools.git) {
    programs.git = {
      enable = true;
      lfs.enable = lib.mkDefault true;

      aliases = lib.mkDefault {
        s = "switch";
        f = "fetch";
        p = "pull";
        b = "branch";
        st = "status -sb";
        co = "checkout";
        c = "commit";
      };

      extraConfig = lib.mkDefault {
        push.autoSetupRemote = true;
        init.defaultBranch = "main";
      };
    };

    programs.lazygit.enable = lib.mkDefault true;

    home.packages = with pkgs; [
      lazygit
    ];
  };
}
