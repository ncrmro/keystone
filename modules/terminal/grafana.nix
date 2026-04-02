# Keystone Terminal Grafana MCP Integration
#
# Provides Grafana MCP server configuration for AI coding tools.
# When enabled, adds the `grafana` MCP server to all configured CLI coding
# agents (Claude Code, Gemini CLI, Codex, OpenCode) and exports the
# GRAFANA_API_KEY environment variable from the agenix runtime secret.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.grafana = {
#   mcp.enable = true;
#   mcp.url = "https://grafana.example.com";
# };
# ```
#
# Implements: https://github.com/ncrmro/keystone/issues/249
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.grafana;

  # Wrapper script that sources the runtime GRAFANA_API_KEY secret so that
  # MCP server processes spawned by Codex (or any CLI) always have the
  # credential available, regardless of whether the parent shell sourced it.
  grafanaMcpWrapper = pkgs.writeShellScript "grafana-mcp-wrapper" ''
    if [ -f /run/agenix/grafana-api-token ]; then
      export GRAFANA_API_KEY="$(${pkgs.coreutils}/bin/tr -d '\n' < /run/agenix/grafana-api-token)"
    fi
    exec ${pkgs.keystone.grafana-mcp}/bin/mcp-grafana "$@"
  '';
in
{
  options.keystone.terminal.grafana = {
    mcp = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Grafana MCP server for AI coding tools, providing access to Prometheus metrics and Loki logs.";
      };

      url = mkOption {
        type = types.str;
        default = "";
        example = "https://grafana.example.com";
        description = "Grafana URL for the MCP server connection.";
      };
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.mcp.enable) {
    assertions = [
      {
        assertion = cfg.mcp.url != "";
        message = "keystone.terminal.grafana.mcp.url must be set when keystone.terminal.grafana.mcp.enable is true";
      }
    ];

    keystone.terminal.cliCodingAgents.mcpServers.grafana = {
      command = "${grafanaMcpWrapper}";
      args = [ ];
      env = {
        GRAFANA_URL = cfg.mcp.url;
      };
    };

    # Export GRAFANA_API_KEY from agenix secret for interactive shell sessions.
    # MCP server processes use the wrapper script above instead.
    programs.zsh.envExtra = ''
      if [ -f /run/agenix/grafana-api-token ]; then
        export GRAFANA_API_KEY="$(${pkgs.coreutils}/bin/tr -d '\n' < /run/agenix/grafana-api-token)"
      fi
    '';
  };
}
