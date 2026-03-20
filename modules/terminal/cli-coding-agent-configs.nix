{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.keystone.terminal.cliCodingAgents;
  terminalCfg = config.keystone.terminal;
in {
  options.keystone.terminal.cliCodingAgents = {
    enable = mkEnableOption "global configurations for AI coding agent CLIs";

    mcpServers = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          command = mkOption {
            type = types.str;
            description = "The command to run the MCP server.";
          };
          args = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Arguments to pass to the MCP server command.";
          };
          env = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = ''
              Environment variables for the MCP server.
              WARNING: These values are stored in the Nix store in plain text and are world-readable.
              DO NOT put secrets (API keys, tokens) here. Use agent-specific environment variables
              or credential managers instead.
            '';
          };
        };
      });
      default = {};
      description = "MCP servers to configure globally across supported AI CLIs.";
    };

    respectGitIgnore = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether Gemini CLI should respect .gitignore files.
        Setting this to false may leak ignored secrets into the AI context.
      '';
    };
  };

  config = mkIf (terminalCfg.enable && cfg.enable) {
    home.file = {
      # Gemini CLI
      # Location: ~/.gemini/settings.json
      ".gemini/settings.json".text = builtins.toJSON {
        mcpServers = cfg.mcpServers;
        context = {
          fileFiltering = {
            inherit (cfg) respectGitIgnore;
          };
        };
      };

      # Claude Code / Claude Desktop
      # Location: ~/.claude.json
      ".claude.json".text = builtins.toJSON {
        mcpServers = cfg.mcpServers;
      };

      # OpenCode
      # Location: ~/.config/opencode/opencode.json
      ".config/opencode/opencode.json".text = builtins.toJSON {
        mcp = mapAttrs (_: srv: {
          type = "local";
          command = [ srv.command ] ++ srv.args;
          enabled = true;
        } // optionalAttrs (srv.env != {}) {
          inherit (srv) env;
        }) cfg.mcpServers;
      };

      # TODO: Enable when codex supports global settings file
      # ".codex/settings.json".text = builtins.toJSON {
      #   mcpServers = cfg.mcpServers;
      # };
    };
  };
}
