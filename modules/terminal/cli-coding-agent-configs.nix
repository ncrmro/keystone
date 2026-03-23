# CLI Coding Agent MCP Configuration
#
# Generates MCP server configs at each AI coding tool's expected path
# (~/.claude.json, ~/.gemini/settings.json, ~/.config/opencode/opencode.json).
#
# See conventions/tool.cli-coding-agents.md
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.keystone.terminal.cliCodingAgents;
  terminalCfg = config.keystone.terminal;

  # Nix-managed MCP servers as a JSON file in the store, used by the
  # activation script to merge into the runtime ~/.claude.json.
  claudeJsonMcpServers = pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON cfg.mcpServers);
in
{
  options.keystone.terminal.cliCodingAgents = {
    enable = mkEnableOption "global configurations for AI coding agent CLIs";

    mcpServers = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            command = mkOption {
              type = types.str;
              description = "The command to run the MCP server.";
            };
            args = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Arguments to pass to the MCP server command.";
            };
            env = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = ''
                Environment variables for the MCP server.
                WARNING: These values are stored in the Nix store in plain text and are world-readable.
                DO NOT put secrets (API keys, tokens) here. Use agent-specific environment variables
                or credential managers instead.
              '';
            };
          };
        }
      );
      default = { };
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
      # TODO: DeepWork is currently installed via the claude plugin for Claude.
      # Ideally, this should be avoided and DeepWork should be configured
      # globally by Nix via `cfg.mcpServers` for all tools. For now, we inject
      # it only into Gemini's MCP config.
      ".gemini/settings.json".text = builtins.toJSON {
        mcpServers = cfg.mcpServers // (
          if terminalCfg.ai.enable then {
            deepwork = {
              command = "${pkgs.keystone.deepwork}/bin/deepwork";
              args = [
                "serve"
                "--path"
                "."
                "--external-runner"
                "gemini"
                "--platform"
                "gemini"
              ];
            };
          } else {}
        );
        context = {
          fileFiltering = {
            inherit (cfg) respectGitIgnore;
          };
        };
      };

      # OpenCode
      # Location: ~/.config/opencode/opencode.json
      ".config/opencode/opencode.json".text = builtins.toJSON {
        mcp = mapAttrs (
          _: srv:
          {
            type = "local";
            command = [ srv.command ] ++ srv.args;
            enabled = true;
          }
          // optionalAttrs (srv.env != { }) {
            inherit (srv) env;
          }
        ) cfg.mcpServers;
      };

      # TODO: Enable when codex supports global settings file
      # ".codex/settings.json".text = builtins.toJSON {
      #   mcpServers = cfg.mcpServers;
      # };
    };

    # Claude Code / Claude Desktop
    # CRITICAL: ~/.claude.json must be a writable regular file, not a Nix store
    # symlink. Claude Code writes runtime state to this file (feature flags,
    # subscription cache, OAuth account, MCP sync). A read-only symlink causes
    # an infinite retry loop that hangs Claude Code forever.
    # Strategy: merge only the mcpServers key from Nix config into the existing
    # file, preserving all Claude Code runtime state.
    home.activation.claudeJsonConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      claudeJson="$HOME/.claude.json"

      # Remove stale Nix store symlink from previous home-manager generations
      if [ -L "$claudeJson" ]; then
        rm -f "$claudeJson"
      fi

      if [ -f "$claudeJson" ]; then
        # Merge: replace only .mcpServers, preserve all other runtime state
        ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: .[1]}' \
          "$claudeJson" ${claudeJsonMcpServers} > "$claudeJson.tmp" \
          && mv "$claudeJson.tmp" "$claudeJson"
      else
        # First run: create with just MCP servers, Claude Code populates the rest
        ${pkgs.jq}/bin/jq -n --slurpfile s ${claudeJsonMcpServers} '{mcpServers: $s[0]}' \
          > "$claudeJson"
      fi
    '';
  };
}
