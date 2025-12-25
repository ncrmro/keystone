{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
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
      nil # Nix LSP
    ];

    programs.helix = {
      enable = true;
      settings = {
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
          nil = {
            command = "${pkgs.nil}/bin/nil";
          };
        };

        language = [
          {
            name = "nix";
            auto-format = true;
            formatter.command = "${pkgs.nixfmt-classic}/bin/nixfmt";
            language-servers = [ "nil" ];
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
