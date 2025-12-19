{
  config,
  lib,
  ...
}:
with lib;
{
  imports = [
    ./shell.nix
    ./editor.nix
    ./ai.nix
  ];

  options.keystone.terminal = {
    enable = mkEnableOption "Keystone Terminal - Core terminal tools and configuration";
    editor = mkOption {
      type = types.str;
      default = "hx";
      description = "Default editor command (e.g., 'hx' for helix, 'nvim' for neovim)";
    };
  };
}
