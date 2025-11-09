{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminal-dev-environment;
in {
  config = lib.mkIf (cfg.enable && cfg.tools.shell) {
    programs.zsh = {
      enable = true;
      enableCompletion = lib.mkDefault true;
      autosuggestion.enable = lib.mkDefault true;
      syntaxHighlighting.enable = lib.mkDefault true;

      shellAliases = {
        l = lib.mkDefault "eza -1l";
        ls = lib.mkDefault "eza -1l";
        grep = lib.mkDefault "rg";
        g = lib.mkDefault "git";
        lg = lib.mkDefault "lazygit";
        hx = lib.mkDefault "helix";
        zs = lib.mkDefault "zesh"; # Zellij session manager with zoxide integration
        # Note: 'z' command is provided by zoxide's shell integration
      };

      history.size = lib.mkDefault 100000;

      oh-my-zsh = {
        enable = lib.mkDefault true;
        plugins = ["git" "colored-man-pages"];
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
      zesh # zesh package available via overlay
    ];
  };
}
