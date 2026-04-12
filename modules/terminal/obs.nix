# Keystone Terminal OBS MCP Integration
#
# Automatically adds the obs-mcp MCP server to all configured CLI coding
# agents (Claude Code, Gemini CLI, Codex, OpenCode) when OBS Studio and
# the terminal CLI coding agents are both enabled.
#
# obs-mcp connects to the OBS WebSocket server (default: ws://localhost:4455).
# Set OBS_WEBSOCKET_PASSWORD in the environment if OBS WebSocket auth is enabled.
#
# Implements: https://github.com/royshil/obs-mcp
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
with lib;
let
  obsEnabled = osConfig != null && (osConfig.keystone.desktop.obs.enable or false);
in
{
  config = mkIf (config.keystone.terminal.enable && config.keystone.terminal.cliCodingAgents.enable && obsEnabled) {
    keystone.terminal.cliCodingAgents.mcpServers.obs = {
      command = "${pkgs.keystone.obs-mcp}/bin/obs-mcp";
      args = [ ];
    };
  };
}
