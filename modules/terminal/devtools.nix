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
  config = mkIf (cfg.enable && cfg.devTools) {
    home.packages = with pkgs; [
      # Csview - CSV viewer for terminal
      # https://github.com/wfxr/csview
      csview
      # MermaidTUI - Mermaid diagram renderer for the terminal
      # https://github.com/tariqshams/mermaidtui
      keystone.mermaidtui
    ];
  };
}
