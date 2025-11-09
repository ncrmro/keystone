{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
  # Import zesh package from flake
  zesh = pkgs.callPackage ../../../packages/zesh { };
in
{
  config = lib.mkIf (cfg.enable && cfg.tools.shell) {
    programs.zsh = {
      enable = true;
      enableCompletion = lib.mkDefault true;
      autosuggestion.enable = lib.mkDefault true;
      syntaxHighlighting.enable = lib.mkDefault true;

      shellAliases = lib.mkDefault {
        l = "eza -1l";
        ls = "eza -1l";
        grep = "rg";
        g = "git";
        lg = "lazygit";
        hx = "helix";
        z = "zoxide";
      };

      history.size = lib.mkDefault 100000;

      oh-my-zsh = {
        enable = lib.mkDefault true;
        plugins = [ "git" "colored-man-pages" ];
        theme = "robbyrussell";
      };
    };

    programs.starship.enable = lib.mkDefault true;

    programs.zoxide = {
      enable = lib.mkDefault true;
      enableZshIntegration = true;
    };

    programs.direnv = {
      enable = lib.mkDefault true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    home.packages = with pkgs; [
      eza
      ripgrep
      tree
      jq
      htop
      zesh
    ];
  };
}
