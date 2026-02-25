# Keystone OS Agents Module
#
# Creates agent users with:
# - NixOS user accounts in the agents group (no sudo, no wheel)
# - UIDs from the 4000+ reserved range
# - Home directories at /home/agent-{name} (ZFS dataset or ext4)
# - chmod 700 isolation between agents
# - Optional headless Wayland desktop (labwc + wayvnc) for remote viewing
#
# Usage:
#   keystone.os.agents.researcher = {
#     fullName = "Research Agent";
#     email = "researcher@example.com";
#     desktop.enable = true;  # headless Wayland + VNC
#   };
#
# Security: VNC binds to 127.0.0.1 only. For remote access, use SSH port
# forwarding (ssh -L 5901:127.0.0.1:5901 host) or Tailscale funnel.
# wayvnc supports TLS but it is not yet configured here.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.agents;

  useZfs = osCfg.storage.type == "zfs";

  # Base UID for agent users
  agentUidBase = 4000;

  # Base VNC port for auto-assignment
  vncPortBase = 5900;

  # Agent submodule type definition
  agentSubmodule = types.submodule (
    { name, ... }:
    {
      options = {
        uid = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "User ID. If null, auto-assigned from the 4000+ range.";
        };

        fullName = mkOption {
          type = types.str;
          description = "Display name for the agent";
          example = "Research Agent";
        };

        email = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Email address for the agent (used for git config and mail provisioning)";
          example = "researcher@ks.systems";
        };

        terminal = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable terminal development environment (zsh, helix, zellij, git)";
          };
        };

        desktop = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable headless Wayland desktop with remote viewing via VNC";
          };

          resolution = mkOption {
            type = types.str;
            default = "1920x1080";
            description = "Desktop resolution (WxH)";
          };

          vncPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "VNC port. If null, auto-assigned starting from 5901.";
          };
        };
      };
    }
  );

  # Sorted agent names for deterministic UID assignment
  sortedAgentNames = sort lessThan (attrNames cfg);

  # Auto-assign UIDs to agents that don't have explicit ones
  agentWithUid =
    name: agentCfg:
    let
      idx =
        findFirst (i: elemAt sortedAgentNames i == name)
          (throw "agent '${name}' not found in sortedAgentNames")
          (genList (x: x) (length sortedAgentNames));
      autoUid = agentUidBase + 1 + idx;
    in
    agentCfg
    // {
      uid = if agentCfg.uid != null then agentCfg.uid else autoUid;
    };

  agentsWithUids = mapAttrs agentWithUid cfg;

  # Desktop-enabled agents
  desktopAgents = filterAttrs (_: a: a.desktop.enable) cfg;
  hasDesktopAgents = desktopAgents != { };

  # Sorted desktop agent names for deterministic VNC port assignment
  sortedDesktopAgentNames = sort lessThan (attrNames desktopAgents);

  # Resolve VNC port for a desktop agent
  agentVncPort =
    name: agentCfg:
    if agentCfg.desktop.vncPort != null then
      agentCfg.desktop.vncPort
    else
      let
        idx = findFirst (
          i: elemAt sortedDesktopAgentNames i == name
        ) (throw "desktop agent '${name}' not found") (genList (x: x) (length sortedDesktopAgentNames));
      in
      vncPortBase + 1 + idx;

  # Generate labwc config for an agent's home directory setup script
  labwcConfigScript =
    username: agentCfg:
    optionalString agentCfg.desktop.enable ''
        # Create labwc config directory
        mkdir -p /home/${username}/.config/labwc
        # autostart: create virtual output for headless VNC
        cat > /home/${username}/.config/labwc/autostart <<'AUTOSTART'
        # Create virtual output for headless VNC
        ${pkgs.wlr-randr}/bin/wlr-randr --output HEADLESS-1 --custom-mode ${agentCfg.desktop.resolution}
      AUTOSTART
        chmod +x /home/${username}/.config/labwc/autostart
        # rc.xml: minimal labwc config
        cat > /home/${username}/.config/labwc/rc.xml <<'RCXML'
      <?xml version="1.0"?>
      <labwc_config>
        <theme><name>default</name></theme>
      </labwc_config>
      RCXML
        chown -R ${username}:agents /home/${username}/.config
    '';
in
{
  options.keystone.os.agents = mkOption {
    type = types.attrsOf agentSubmodule;
    default = { };
    description = ''
      Agent users with automatic NixOS user creation and home directory isolation.
      Agents are non-interactive users (no password login, no sudo) designed for
      LLM-driven autonomous operation.
    '';
    example = literalExpression ''
      {
        researcher = {
          fullName = "Research Agent";
          email = "researcher@ks.systems";
          desktop.enable = true;
        };
      }
    '';
  };

  config = mkIf (osCfg.enable && cfg != { }) (mkMerge [
    # Base agent configuration
    {
      assertions = [
        # All agent UIDs must be unique
        {
          assertion =
            let
              uids = mapAttrsToList (_: a: a.uid) agentsWithUids;
              uniqueUids = unique uids;
            in
            length uids == length uniqueUids;
          message = "All agent UIDs must be unique";
        }
        # Agent UIDs must not collide with human user UIDs
        {
          assertion =
            let
              agentUids = mapAttrsToList (_: a: a.uid) agentsWithUids;
              humanUids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) osCfg.users);
            in
            all (aUid: !elem aUid humanUids) agentUids;
          message = "Agent UIDs must not collide with human user UIDs";
        }
      ];

      # Create the agents group
      users.groups.agents = { };

      # Enable zsh if any agent has terminal enabled
      programs.zsh.enable = mkIf (any (a: a.terminal.enable) (attrValues cfg)) true;

      # Generate NixOS users for agents
      users.users = mapAttrs' (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
        in
        nameValuePair username {
          isNormalUser = true;
          uid = resolved.uid;
          description = agentCfg.fullName;
          home = "/home/${username}";
          createHome = !useZfs;
          group = "agents";
          extraGroups = optionals useZfs [ "zfs" ];
          shell = mkIf agentCfg.terminal.enable pkgs.zsh;
          # No password -- agents are non-interactive
        }
      ) cfg;

      # Home directory creation for ext4
      systemd.services.create-agent-homes = mkIf (!useZfs) {
        description = "Create and configure agent home directories";

        wantedBy = [ "multi-user.target" ];
        before = [ "systemd-user-sessions.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: agentCfg:
              let
                username = "agent-${name}";
              in
              ''
                if [ ! -d /home/${username} ]; then
                  mkdir -p /home/${username}
                fi
                chown ${username}:agents /home/${username}
                chmod 700 /home/${username}

                ${labwcConfigScript username agentCfg}
              ''
            ) cfg
          )}
        '';
      };

      # ZFS dataset creation for agent homes
      systemd.services.zfs-agent-datasets = mkIf useZfs {
        description = "Create ZFS datasets for agent home directories";

        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-mount.service" ];
        before = [ "systemd-user-sessions.service" ];
        requires = [ "zfs-mount.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        path = [ config.boot.zfs.package ];

        script = ''
          set -euo pipefail

          # Create parent home dataset if needed
          if ! zfs list -H -o name rpool/crypt/home > /dev/null 2>&1; then
            zfs create -o mountpoint=/home rpool/crypt/home
          fi

          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: agentCfg:
              let
                username = "agent-${name}";
              in
              ''
                zfs create -p -o mountpoint=/home/${username} rpool/crypt/home/${username} 2>/dev/null || true
                zfs set compression=lz4 rpool/crypt/home/${username}
                chown ${username}:agents /home/${username}
                chmod 700 /home/${username}

                ${labwcConfigScript username agentCfg}
              ''
            ) cfg
          )}
        '';
      };
    }

    # Desktop agent configuration (labwc + wayvnc)
    (mkIf hasDesktopAgents {
      assertions = [
        # All VNC ports must be unique
        {
          assertion =
            let
              ports = mapAttrsToList (name: a: agentVncPort name a) desktopAgents;
              uniquePorts = unique ports;
            in
            length ports == length uniquePorts;
          message = "All agent VNC ports must be unique";
        }
      ];

      # Enable labwc system-wide
      programs.labwc.enable = true;

      # System packages for desktop agents
      environment.systemPackages = [
        pkgs.wayvnc
        pkgs.wlr-randr
      ];

      # Systemd target grouping all agent desktop services
      systemd.targets.agent-desktops = {
        description = "All agent headless desktop services";
        wantedBy = [ "multi-user.target" ];
      };

      # labwc + wayvnc services per desktop agent
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            port = agentVncPort name agentCfg;
            waylandDisplay = "wayland-agent-${name}";
            xdgRuntimeDir = "/run/user/${toString uid}";
          in
          {
            # labwc headless compositor
            "labwc-agent-${name}" = {
              description = "Headless Wayland desktop for agent-${name}";

              wantedBy = [ "agent-desktops.target" ];
              after = [
                "multi-user.target"
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
              ];
              requires = [
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
              ];

              environment = {
                WLR_BACKENDS = "headless";
                WLR_LIBINPUT_NO_DEVICES = "1";
                WAYLAND_DISPLAY = waylandDisplay;
                XDG_RUNTIME_DIR = xdgRuntimeDir;
                XDG_CONFIG_HOME = "/home/${username}/.config";
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                RuntimeDirectory = "user/${toString uid}";
                RuntimeDirectoryMode = "0700";
                ExecStart = "${pkgs.labwc}/bin/labwc";
                Restart = "always";
                RestartSec = 5;
              };
            };

            # wayvnc remote viewing (localhost only -- see module header for security notes)
            "wayvnc-agent-${name}" = {
              description = "VNC server for agent-${name} desktop";

              wantedBy = [ "agent-desktops.target" ];
              after = [ "labwc-agent-${name}.service" ];
              requires = [ "labwc-agent-${name}.service" ];

              environment = {
                WAYLAND_DISPLAY = waylandDisplay;
                XDG_RUNTIME_DIR = xdgRuntimeDir;
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                # Wait for labwc to create the Wayland socket and virtual output
                ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
                ExecStart = "${pkgs.wayvnc}/bin/wayvnc 127.0.0.1 ${toString port}";
                Restart = "always";
                RestartSec = 5;
              };
            };
          }
        ) desktopAgents
      );
    })
  ]);
}
