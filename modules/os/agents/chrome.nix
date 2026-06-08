# Chromium remote debugging services for agents.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib)
    osCfg
    cfg
    agentsWithUids
    useZfs
    ;
  inherit (agentsLib) chromeAgents hasChromeAgents agentChromeDebugPort;
in
{
  config = mkIf (osCfg.enable && cfg != { } && hasChromeAgents) {
    assertions = [
      # All Chrome debug ports must be unique
      {
        assertion =
          let
            ports = mapAttrsToList (name: a: agentChromeDebugPort name a) chromeAgents;
            uniquePorts = unique ports;
          in
          length ports == length uniquePorts;
        message = "All agent Chrome debug ports must be unique";
      }
    ];

    # Chromium and Node.js available system-wide for chrome agents.
    # Node.js is required for the chrome-devtools-mcp server (stdio transport via npx/node).
    environment.systemPackages = [
      pkgs.chromium
      pkgs.nodejs
    ];

    # Chromium as system services per chrome agent
    #
    # Why system services and not systemd.user.services:
    # 1. NixOS switch-to-configuration does not manage user services — it only
    #    reloads the user daemon (daemon-reload) but won't start/restart units
    #    added to default.target.wants after the target is already reached.
    # 2. system.activationScripts with `systemctl --user -M user@` fails with
    #    "Transport endpoint is not connected" — machinectl can't reach the
    #    user's D-Bus from PID 1 context during activation.
    # 3. A system-level helper using `runuser` can connect to the user bus, but
    #    the chromium user service's ExecStartPre (Wayland socket poll) times
    #    out because the environment isn't fully forwarded through runuser.
    #
    # System services with User=/Group= work reliably: switch-to-configuration
    # manages restarts, and After=/Requires= on labwc ensures proper ordering.
    systemd.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
          uid = resolved.uid;
          debugPort = agentChromeDebugPort name agentCfg;
          xdgRuntimeDir = "/run/user/${toString uid}";
          profileDir = "/home/${username}/.config/chromium-agent";
          isHeadless = agentCfg.chrome.mode == "headless";
          homeReadyUnit = if useZfs then "zfs-agent-datasets.service" else "agent-homes.service";
          waylandReadyCheck = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 100); do [ -S \"${xdgRuntimeDir}/wayland-0\" ] && exit 0; sleep 0.1; done; echo \"Timed out waiting for Wayland socket\" >&2; exit 1'";
          chromiumArgs = [
            "${pkgs.chromium}/bin/chromium"
            "--user-data-dir=${profileDir}"
            "--remote-debugging-port=${toString debugPort}"
            "--remote-debugging-address=127.0.0.1"
            "--no-first-run"
            "--no-default-browser-check"
            "--disable-gpu"
          ]
          ++ optionals isHeadless [
            "--headless=new"
            "--disable-dev-shm-usage"
          ]
          ++ optionals (!isHeadless) [
            "--enable-features=UseOzonePlatform"
            "--ozone-platform=wayland"
          ];
          healthCheck = pkgs.writeShellScript "agent-${name}-chromium-healthcheck" ''
            set -eu

            port="${toString debugPort}"
            url="http://127.0.0.1:$port"
            service="agent-${name}-chromium.service"

            if ! ${pkgs.curl}/bin/curl -fsS --max-time 5 "$url/json/version" >/dev/null; then
              echo "$service: DevTools version endpoint failed; restarting" >&2
              exec ${pkgs.systemd}/bin/systemctl restart "$service"
            fi

            if ! ${pkgs.curl}/bin/curl -fsS --max-time 5 "$url/json/list" >/dev/null; then
              echo "$service: DevTools target list endpoint failed; restarting" >&2
              exec ${pkgs.systemd}/bin/systemctl restart "$service"
            fi

            ${optionalString agentCfg.chrome.healthCheck.probeMcp ''
              probe="$(${pkgs.coreutils}/bin/mktemp --suffix=.mjs)"
              trap 'rm -f "$probe"' EXIT
              cat > "$probe" <<'EOF'
              import { Client } from '${pkgs.keystone.pi-mcp-extension}/lib/node_modules/pi-mcp-extension/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
              import { StdioClientTransport } from '${pkgs.keystone.pi-mcp-extension}/lib/node_modules/pi-mcp-extension/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';

              const transport = new StdioClientTransport({
                command: '${pkgs.keystone.chrome-devtools-mcp}/bin/chrome-devtools-mcp',
                args: [
                  '--browserUrl',
                  'http://127.0.0.1:${toString debugPort}',
                  '--no-usage-statistics',
                  '--no-performance-crux',
                ],
              });
              const client = new Client({ name: 'keystone-healthcheck', version: '0.0.0' }, { capabilities: {} });

              try {
                await client.connect(transport);
                await client.callTool({ name: 'list_pages', arguments: {} });
              } finally {
                await client.close();
              }
              EOF

              if ! ${pkgs.coreutils}/bin/timeout 20 ${pkgs.nodejs}/bin/node "$probe"; then
                echo "$service: Chrome DevTools MCP list_pages probe failed; restarting" >&2
                exec ${pkgs.systemd}/bin/systemctl restart "$service"
              fi
            ''}
          '';
        in
        {
          "agent-${name}-chromium" = {
            description = "Chromium browser for ${username}";
            after = if isHeadless then [ homeReadyUnit ] else [ "agent-${name}-labwc.service" ];
            requires = if isHeadless then [ homeReadyUnit ] else [ "agent-${name}-labwc.service" ];
            wantedBy = if isHeadless then [ "multi-user.target" ] else [ "agent-desktops.target" ];
            environment = {
              XDG_CONFIG_HOME = "/home/${username}/.config";
            }
            // optionalAttrs isHeadless {
              XDG_RUNTIME_DIR = xdgRuntimeDir;
            }
            // optionalAttrs (!isHeadless) {
              WAYLAND_DISPLAY = "wayland-0";
              XDG_RUNTIME_DIR = xdgRuntimeDir;
            };
            serviceConfig = {
              Type = "simple";
              User = username;
              Group = "agents";
              ExecStart = builtins.concatStringsSep " " chromiumArgs;
              Restart = "always";
              RestartSec = 5;
            }
            // optionalAttrs isHeadless {
              RuntimeDirectory = "user/${toString uid}";
              RuntimeDirectoryMode = "0700";
            }
            // optionalAttrs (!isHeadless) {
              # Poll for Wayland socket before starting Chromium
              ExecStartPre = waylandReadyCheck;
            };
          };

          "agent-${name}-chromium-healthcheck" = {
            description = "Health check Chromium DevTools for ${username}";
            after = [ "agent-${name}-chromium.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = healthCheck;
            };
          };
        }
      ) chromeAgents
    );

    systemd.timers = mkMerge (
      mapAttrsToList (name: agentCfg: {
        "agent-${name}-chromium-healthcheck" = mkIf agentCfg.chrome.healthCheck.enable {
          description = "Periodic Chromium DevTools health check for agent-${name}";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitActiveSec = agentCfg.chrome.healthCheck.interval;
            AccuracySec = "30s";
            Unit = "agent-${name}-chromium-healthcheck.service";
          };
        };
      }) chromeAgents
    );
  };
}
