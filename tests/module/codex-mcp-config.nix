# Codex MCP configuration validation test
#
# Verifies that the generated Codex MCP configuration contains the expected
# MCP server entries when features are enabled.  Evaluates a home-manager
# configuration and inspects the resolved `generatedMcpServers.codex` attrset
# at Nix-evaluation time — no VM boot required.
#
# Covers:
#   - Grafana MCP registration when grafana.mcp.enable = true
#   - DeepWork MCP registration preserved alongside Grafana
#   - Codex MCP JSON content written to Nix store
#
# Build: nix build .#codex-mcp-config
#
{
  pkgs,
  lib,
  self,
  home-manager,
}:
let
  hmConfig = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeModules.notes
      self.homeModules.terminal
      {
        nixpkgs.overlays = [ self.overlays.default ];
        home.username = "testuser";
        home.homeDirectory = "/home/testuser";
        home.stateVersion = "25.05";

        keystone.projects.enable = false;
        keystone.terminal = {
          enable = true;
          sandbox.enable = false;
          git = {
            userName = "Test User";
            userEmail = "testuser@example.com";
          };

          # Enable Grafana MCP
          grafana.mcp = {
            enable = true;
            url = "https://grafana.test.example.com";
          };
        };
      }
    ];
  };

  codexMcpServers =
    hmConfig.config.keystone.terminal.cliCodingAgents.generatedMcpServers.codex or { };
  codexMcpJson = builtins.toJSON codexMcpServers;
in
pkgs.runCommand "codex-mcp-config-check" { } ''
  mcp_json='${codexMcpJson}'

  echo "Codex MCP servers JSON:"
  echo "$mcp_json" | ${pkgs.jq}/bin/jq .

  echo ""
  echo "=== Checking Grafana MCP registration ==="

  if echo "$mcp_json" | ${pkgs.jq}/bin/jq -e '.grafana' > /dev/null 2>&1; then
    echo "  ✓ grafana MCP server is registered"
  else
    echo "  ✗ FAIL: grafana MCP server is NOT registered"
    exit 1
  fi

  if echo "$mcp_json" | ${pkgs.jq}/bin/jq -e '.grafana.command' > /dev/null 2>&1; then
    echo "  ✓ grafana MCP server has a command"
  else
    echo "  ✗ FAIL: grafana MCP server is missing command"
    exit 1
  fi

  if echo "$mcp_json" | ${pkgs.jq}/bin/jq -r '.grafana.env.GRAFANA_URL' | grep -q 'grafana.test.example.com'; then
    echo "  ✓ grafana MCP server has correct GRAFANA_URL"
  else
    echo "  ✗ FAIL: grafana MCP server has wrong or missing GRAFANA_URL"
    echo "    Actual: $(echo "$mcp_json" | ${pkgs.jq}/bin/jq -r '.grafana.env.GRAFANA_URL')"
    exit 1
  fi

  echo ""
  echo "=== Checking DeepWork MCP preservation ==="

  if echo "$mcp_json" | ${pkgs.jq}/bin/jq -e '.deepwork' > /dev/null 2>&1; then
    echo "  ✓ deepwork MCP server is still registered"
  else
    echo "  ✗ FAIL: deepwork MCP server was lost"
    exit 1
  fi

  if echo "$mcp_json" | ${pkgs.jq}/bin/jq -r '.deepwork.args[]' | grep -q 'codex'; then
    echo "  ✓ deepwork MCP server uses codex platform"
  else
    echo "  ✗ FAIL: deepwork MCP server missing codex platform flag"
    exit 1
  fi

  echo ""
  echo "=== All Codex MCP config checks passed ==="
  touch "$out"
''
