{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
in
{
  meta.maintainers = [ ];

  imports = [
    ../omarchy-theming
    ./git.nix
    ./helix.nix
    ./zsh.nix
    ./zellij.nix
    ./ghostty.nix
  ];

  options.programs.terminal-dev-environment = {
    enable = lib.mkEnableOption "terminal development environment";

    tools = {
      git = lib.mkEnableOption "Git and Git UI tools" // { default = true; };
      editor = lib.mkEnableOption "Helix text editor" // { default = true; };
      shell = lib.mkEnableOption "Zsh shell with utilities" // { default = true; };
      multiplexer = lib.mkEnableOption "Zellij terminal multiplexer" // { default = true; };
      terminal = lib.mkEnableOption "Ghostty terminal emulator" // { default = true; };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.ripgrep pkgs.fd pkgs.bat ]";
      description = "Additional packages to include in the terminal development environment";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = cfg.extraPackages;
  };
}
