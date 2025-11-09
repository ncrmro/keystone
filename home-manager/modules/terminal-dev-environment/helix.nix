{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
  themingCfg = config.programs.omarchy-theming or { };
  
  # Check if theming is enabled and helix theming is specifically enabled
  themingEnabled = themingCfg.enable or false 
    && themingCfg.terminal.enable or false 
    && themingCfg.terminal.applications.helix or false;
    
  # Path to omarchy helix theme config (if it exists)
  # Note: The integration method depends on the actual structure of helix.toml in omarchy themes
  # This may need adjustment based on whether it's a theme file or config override
  themePath = "${config.xdg.configHome}/omarchy/current/theme/helix.toml";
in
{
  config = lib.mkIf (cfg.enable && cfg.tools.editor) {
    home.sessionVariables = {
      EDITOR = "hx";
      VISUAL = "hx";
    };

    home.packages = with pkgs; [
      bash-language-server
      yaml-language-server
      dockerfile-language-server-nodejs
      vscode-langservers-extracted
      marksman
      nixfmt-classic
    ];

    programs.helix = {
      enable = true;
      
      # When theming is enabled, we'll merge/include the omarchy theme config
      # The exact method depends on the structure of omarchy's helix.toml file
      # TODO: Test with actual omarchy theme to determine if this is a theme file
      # or a config overlay that should be merged into settings
      
      settings = {
        # Default theme when omarchy theming is not enabled
        theme = lib.mkDefault "default";
        editor = {
          line-number = "relative";
          mouse = true;
          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
        };
      };

      languages = {
        language-server = {
          bash-language-server = {
            command = "${pkgs.bash-language-server}/bin/bash-language-server";
            args = [ "start" ];
          };
          yaml-language-server = {
            command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
            args = [ "--stdio" ];
          };
          dockerfile-language-server = {
            command = "${pkgs.dockerfile-language-server-nodejs}/bin/docker-langserver";
            args = [ "--stdio" ];
          };
          vscode-json-language-server = {
            command = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
            args = [ "--stdio" ];
          };
          marksman = {
            command = "${pkgs.marksman}/bin/marksman";
            args = [ "server" ];
          };
        };

        language = [
          {
            name = "nix";
            auto-format = true;
            formatter.command = "${pkgs.nixfmt-classic}/bin/nixfmt";
          }
          {
            name = "bash";
            language-servers = [ "bash-language-server" ];
          }
          {
            name = "yaml";
            language-servers = [ "yaml-language-server" ];
          }
          {
            name = "dockerfile";
            language-servers = [ "dockerfile-language-server" ];
          }
          {
            name = "json";
            language-servers = [ "vscode-json-language-server" ];
          }
          {
            name = "markdown";
            language-servers = [ "marksman" ];
          }
        ];
      };
    };
  };
}
