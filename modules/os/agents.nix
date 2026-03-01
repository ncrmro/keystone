# Keystone OS Agents Module
#
# Creates agent users with:
# - NixOS user accounts in the agents group (no sudo, no wheel)
# - UIDs from the 4000+ reserved range
# - Home directories at /home/agent-{name} (ZFS dataset or ext4)
# - chmod 700 isolation between agents
# - Optional headless Wayland desktop (labwc + wayvnc) for remote viewing
# - Optional Chromium browser with remote debugging (chrome.enable)
# - Optional Stalwart mail account with himalaya CLI (mail.enable)
# - Optional Vaultwarden/Bitwarden integration with per-agent collections
# - Optional per-agent Tailscale instances with UID-based routing
# - SSH key management via agenix (ssh-agent + git signing)
#
# Usage:
#   keystone.os.agents.researcher = {
#     fullName = "Research Agent";
#     email = "researcher@example.com";
#     desktop.enable = true;  # headless Wayland + VNC
#     mail.enable = true;     # Stalwart mail + himalaya CLI
#     mail.domain = "ks.systems";
#     bitwarden.enable = true; # Vaultwarden + bw CLI
#     tailscale.enable = true; # per-agent tailscaled instance
#     ssh.publicKey = "ssh-ed25519 AAAAC3...";  # for authorized_keys
#   };
#
# SSH: Each agent gets an ssh-agent systemd service that auto-loads its
# private key from agenix using the passphrase secret. Git is configured
# to sign commits with the SSH key. The agent's public key is added to
# its own ~/.ssh/authorized_keys for sandbox access.
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

  # Base Chrome debug port for auto-assignment
  chromeDebugPortBase = 9222;

  # Base Chrome MCP port for auto-assignment
  chromeMcpPortBase = 3100;

  # Agent submodule type definition
  agentSubmodule = types.submodule (
    {
      name,
      config,
      ...
    }:
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

        chrome = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Chromium browser with remote debugging on the agent's desktop";
          };

          debugPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Chrome remote debugging port. If null, auto-assigned starting from 9222.";
          };

          mcp = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable Chrome DevTools MCP server for the agent's Chromium instance";
            };

            port = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "Chrome DevTools MCP server port. If null, auto-assigned starting from 3101.";
            };
          };
        };

        mail = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Stalwart mail account and himalaya CLI for programmatic email access";
          };

          domain = mkOption {
            type = types.str;
            default = "";
            description = "Mail domain for the agent's email address (e.g., 'ks.systems')";
            example = "ks.systems";
          };

          address = mkOption {
            type = types.str;
            default = "agent-${name}@${if config.mail.domain != "" then config.mail.domain else "localhost"}";
            defaultText = literalExpression ''"agent-{name}@{mail.domain}"'';
            description = "Full email address for the agent. Defaults to agent-{name}@{mail.domain}.";
            example = "agent-researcher@ks.systems";
          };

          host = mkOption {
            type = types.str;
            default = "";
            description = "Mail server hostname. Defaults to empty (must be set when mail.enable is true).";
            example = "mail.ks.systems";
          };

          imap.port = mkOption {
            type = types.int;
            default = 993;
            description = "IMAP port";
          };

          smtp.port = mkOption {
            type = types.int;
            default = 465;
            description = "SMTP port";
          };

          caldav.enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable CalDAV access (provisioned alongside mail account)";
          };

          carddav.enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable CardDAV access (provisioned alongside mail account)";
          };
        };

        bitwarden = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Vaultwarden/Bitwarden integration with bw CLI and agenix-managed password";
          };

          serverUrl = mkOption {
            type = types.str;
            description = "Vaultwarden server URL for bw CLI configuration";
            example = "https://vault.example.com";
          };

          collection = mkOption {
            type = types.str;
            default = "agent-${name}";
            description = "Bitwarden collection name scoped to this agent";
          };
        };

        tailscale = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Enable a per-agent tailscaled instance. When enabled, the agent gets
              its own tailscaled daemon with unique state dir, socket, and TUN
              interface. An nftables fwmark rule routes the agent's UID traffic
              through its dedicated TUN. A tailscale CLI wrapper in the agent's
              PATH auto-specifies --socket for convenience.

              Requires an agenix secret at age.secrets."agent-{name}-tailscale-auth-key".
              When disabled, the agent falls back to the host Tailscale via tailscale0.
            '';
          };
        };

        ssh = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Enable SSH key management for this agent. When enabled, declares
              agenix secrets for the private key and passphrase, creates an
              ssh-agent systemd service that auto-loads the key, configures git
              for SSH commit signing, and adds the public key to authorized_keys.
            '';
          };

          publicKey = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              SSH public key for this agent. Added to the agent's
              ~/.ssh/authorized_keys for sandbox access. Also used as
              the git signing key.
            '';
            example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... agent-researcher";
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

  # Mail-enabled agents
  mailAgents = filterAttrs (_: a: a.mail.enable) cfg;
  hasMailAgents = mailAgents != { };

  # Bitwarden-enabled agents
  bitwardenAgents = filterAttrs (_: a: a.bitwarden.enable) cfg;
  hasBitwardenAgents = bitwardenAgents != { };

  # SSH-enabled agents
  sshAgents = filterAttrs (_: a: a.ssh.enable) cfg;
  hasSshAgents = sshAgents != { };

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

  # Chrome-enabled agents (must also have desktop enabled)
  chromeAgents = filterAttrs (_: a: a.chrome.enable && a.desktop.enable) cfg;
  hasChromeAgents = chromeAgents != { };

  # Sorted chrome agent names for deterministic debug port assignment
  sortedChromeAgentNames = sort lessThan (attrNames chromeAgents);

  # Resolve Chrome debug port for a chrome agent
  agentChromeDebugPort =
    name: agentCfg:
    if agentCfg.chrome.debugPort != null then
      agentCfg.chrome.debugPort
    else
      let
        idx = findFirst (
          i: elemAt sortedChromeAgentNames i == name
        ) (throw "chrome agent '${name}' not found") (genList (x: x) (length sortedChromeAgentNames));
      in
      chromeDebugPortBase + idx;

  # Resolve Chrome MCP port for a chrome agent
  agentChromeMcpPort =
    name: agentCfg:
    if agentCfg.chrome.mcp.port != null then
      agentCfg.chrome.mcp.port
    else
      let
        idx = findFirst (
          i: elemAt sortedChromeAgentNames i == name
        ) (throw "chrome agent '${name}' not found") (genList (x: x) (length sortedChromeAgentNames));
      in
      chromeMcpPortBase + 1 + idx;

  # Tailscale-enabled agents
  tailscaleAgents = filterAttrs (_: a: a.tailscale.enable) cfg;
  hasTailscaleAgents = tailscaleAgents != { };

  # fwmark base for per-agent tailscale routing (one per agent)
  tailscaleFwmarkBase = 51820;
  sortedTailscaleAgentNames = sort lessThan (attrNames tailscaleAgents);

  # Compute fwmark for a tailscale agent
  agentFwmark =
    name:
    let
      idx = findFirst (
        i: elemAt sortedTailscaleAgentNames i == name
      ) (throw "tailscale agent '${name}' not found") (genList (x: x) (length sortedTailscaleAgentNames));
    in
    tailscaleFwmarkBase + 1 + idx;

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

  # Generate himalaya config.toml for a mail-enabled agent
  himalayaConfig =
    name: agentCfg:
    let
      username = "agent-${name}";
      mailAddr = agentCfg.mail.address;
      mailHost = agentCfg.mail.host;
      imapPort = agentCfg.mail.imap.port;
      smtpPort = agentCfg.mail.smtp.port;
      secretPath = "/run/agenix/agent-${name}-mail-password";
    in
    pkgs.writeText "himalaya-config-agent-${name}.toml" ''
      [accounts.${name}]
      email = "${mailAddr}"
      display-name = "${agentCfg.fullName}"
      default = true

      backend.type = "imap"
      backend.host = "${mailHost}"
      backend.port = ${toString imapPort}
      backend.encryption.type = "tls"
      backend.login = "${username}"
      backend.auth.type = "password"
      backend.auth.command = "cat ${secretPath}"

      message.send.backend.type = "smtp"
      message.send.backend.host = "${mailHost}"
      message.send.backend.port = ${toString smtpPort}
      message.send.backend.encryption.type = "tls"
      message.send.backend.login = "${username}"
      message.send.backend.auth.type = "password"
      message.send.backend.auth.command = "cat ${secretPath}"

      # Stalwart folder names (differ from Himalaya defaults)
      folder.aliases.sent = "Sent Items"
      folder.aliases.drafts = "Drafts"
      folder.aliases.trash = "Deleted Items"
    '';

  # Generate himalaya config setup script for home directory creation
  himalayaConfigScript =
    username: agentCfg: name:
    optionalString agentCfg.mail.enable ''
      # Create himalaya config directory
      mkdir -p /home/${username}/.config/himalaya
      cp ${himalayaConfig name agentCfg} /home/${username}/.config/himalaya/config.toml
      chmod 600 /home/${username}/.config/himalaya/config.toml
      chown -R ${username}:agents /home/${username}/.config/himalaya
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
          mail = {
            enable = true;
            domain = "ks.systems";
            host = "mail.ks.systems";
          };
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
          openssh.authorizedKeys.keys =
            optional (agentCfg.ssh.enable && agentCfg.ssh.publicKey != null) agentCfg.ssh.publicKey;
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
                ${himalayaConfigScript username agentCfg name}
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
                ${himalayaConfigScript username agentCfg name}
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
                WLR_RENDERER = "pixman";
                WLR_HEADLESS_OUTPUTS = "1";
                WLR_LIBINPUT_NO_DEVICES = "1";
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
                WAYLAND_DISPLAY = "wayland-0";
                XDG_RUNTIME_DIR = xdgRuntimeDir;
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                # Poll for Wayland socket instead of fixed sleep — labwc startup
                # time varies; this waits up to 10s with 100ms intervals
                ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 100); do [ -S \"${xdgRuntimeDir}/wayland-0\" ] && exit 0; sleep 0.1; done; echo \"Timed out waiting for Wayland socket\" >&2; exit 1'";
                ExecStart = "${pkgs.wayvnc}/bin/wayvnc 127.0.0.1 ${toString port}";
                Restart = "always";
                RestartSec = 5;
              };
            };
          }
        ) desktopAgents
      );
    })

    # Chrome browser configuration (Chromium with remote debugging)
    (mkIf hasChromeAgents {
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
        # Chrome requires desktop
        {
          assertion = all (a: a.desktop.enable) (attrValues (filterAttrs (_: a: a.chrome.enable) cfg));
          message = "chrome.enable requires desktop.enable — Chromium needs a Wayland compositor";
        }
      ];

      # Chromium package available system-wide for chrome agents
      environment.systemPackages = [
        pkgs.chromium
      ];

      # Chromium services per chrome agent
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
          in
          {
            # Chromium browser with remote debugging
            "chromium-agent-${name}" = {
              description = "Chromium browser for agent-${name}";

              wantedBy = [ "agent-desktops.target" ];
              after = [ "labwc-agent-${name}.service" ];
              requires = [ "labwc-agent-${name}.service" ];

              environment = {
                WAYLAND_DISPLAY = "wayland-0";
                XDG_RUNTIME_DIR = xdgRuntimeDir;
                XDG_CONFIG_HOME = "/home/${username}/.config";
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                # Poll for Wayland socket before starting Chromium
                ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 100); do [ -S \"${xdgRuntimeDir}/wayland-0\" ] && exit 0; sleep 0.1; done; echo \"Timed out waiting for Wayland socket\" >&2; exit 1'";
                ExecStart = builtins.concatStringsSep " " [
                  "${pkgs.chromium}/bin/chromium"
                  "--user-data-dir=${profileDir}"
                  "--remote-debugging-port=${toString debugPort}"
                  "--remote-debugging-address=127.0.0.1"
                  "--no-first-run"
                  "--no-default-browser-check"
                  "--disable-gpu"
                  "--enable-features=UseOzonePlatform"
                  "--ozone-platform=wayland"
                ];
                Restart = "always";
                RestartSec = 5;
              };
            };
          }
        ) chromeAgents
      );
    })

    # Mail agent configuration (Stalwart account + himalaya CLI)
    # VM test assertion: /home/agent-{name}/.config/himalaya/config.toml exists
    # for each agent with mail.enable = true
    (mkIf hasMailAgents {
      assertions = [
        # All mail-enabled agents must have a mail domain configured
        {
          assertion = all (a: a.mail.domain != "") (attrValues mailAgents);
          message = "All agents with mail.enable must have mail.domain set";
        }
        # All mail-enabled agents must have a mail host configured
        {
          assertion = all (a: a.mail.host != "") (attrValues mailAgents);
          message = "All agents with mail.enable must have mail.host set";
        }
      ];

      # Install himalaya CLI system-wide for mail-enabled agents
      environment.systemPackages = [
        pkgs.keystone.himalaya
      ];

      # NOTE: Consumer (nixos-config) must declare agenix secrets:
      #   age.secrets."agent-{name}-mail-password" = { file = ...; owner = "agent-{name}"; mode = "0400"; };
    })

    # Bitwarden/Vaultwarden agent configuration
    (mkIf hasBitwardenAgents {
      # Install bitwarden-cli for agents with bitwarden enabled
      environment.systemPackages = [
        pkgs.bitwarden-cli
      ];

      # NOTE: Consumer (nixos-config) must declare agenix secrets:
      #   age.secrets."agent-{name}-bitwarden-password" = { file = ...; owner = "agent-{name}"; mode = "0400"; };

      # Configure bw CLI server URL per bitwarden-enabled agent
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          {
            "bitwarden-config-agent-${name}" = {
              description = "Configure Bitwarden CLI for agent-${name}";

              wantedBy = [ "multi-user.target" ];
              after = [
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
              ];
              requires = [
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
              ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = username;
                Group = "agents";
              };

              script = ''
                # Configure bw CLI to use the Vaultwarden server
                ${pkgs.bitwarden-cli}/bin/bw config server ${agentCfg.bitwarden.serverUrl}
              '';
            };
          }
        ) bitwardenAgents
      );
    })

    # Per-agent Tailscale instances
    (mkIf hasTailscaleAgents {
      # NOTE: Consumer (nixos-config) must declare agenix secrets:
      #   age.secrets."agent-{name}-tailscale-auth-key" = { file = ...; owner = "root"; mode = "0400"; };

      # Systemd target grouping all agent tailscale services
      systemd.targets.agent-tailscale = {
        description = "All per-agent tailscaled services";
        wantedBy = [ "multi-user.target" ];
      };

      # Per-agent tailscaled services + wrapper installer
      systemd.services = mkMerge ((
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            fwmark = agentFwmark name;
            stateDir = "/var/lib/tailscale/tailscaled-agent-${name}.state";
            socketPath = "/run/tailscale/tailscaled-agent-${name}.socket";
            tunName = "tailscale-agent-${name}";
            authKeyPath = "/run/agenix/agent-${name}-tailscale-auth-key";
          in
          {
            "tailscaled-agent-${name}" = {
              description = "Tailscale daemon for agent-${name}";

              wantedBy = [ "agent-tailscale.target" ];
              after = [
                "network-online.target"
                "agenix.service"
              ];
              wants = [ "network-online.target" ];
              requires = [ "agenix.service" ];

              serviceConfig = {
                Type = "notify";
                RuntimeDirectory = "tailscale";
                RuntimeDirectoryPreserve = "yes";
                StateDirectory = "tailscale";
                ExecStart = "${pkgs.tailscale}/bin/tailscaled --state=${stateDir} --socket=${socketPath} --tun=${tunName}";
                ExecStartPost = "${pkgs.tailscale}/bin/tailscale --socket=${socketPath} up --auth-key=file:${authKeyPath} --hostname=agent-${name}";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };

            # nftables fwmark rule: route agent UID traffic through its TUN
            "nftables-agent-${name}" = {
              description = "nftables fwmark routing for agent-${name} via ${tunName}";

              wantedBy = [ "agent-tailscale.target" ];
              after = [ "tailscaled-agent-${name}.service" ];
              requires = [ "tailscaled-agent-${name}.service" ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "nftables-agent-${name}-up" ''
                  set -euo pipefail
                  # Create nftables table and chain for agent UID routing
                  ${pkgs.nftables}/bin/nft add table inet agent-${name} 2>/dev/null || true
                  ${pkgs.nftables}/bin/nft add chain inet agent-${name} output "{ type route hook output priority mangle; }" 2>/dev/null || true
                  ${pkgs.nftables}/bin/nft add rule inet agent-${name} output meta skuid ${toString uid} meta mark set ${toString fwmark}

                  # Add ip rule to route fwmarked traffic through the agent's TUN
                  ${pkgs.iproute2}/bin/ip rule add fwmark ${toString fwmark} table ${toString fwmark} priority ${toString fwmark} 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip route add default dev ${tunName} table ${toString fwmark} 2>/dev/null || true
                '';
                ExecStop = pkgs.writeShellScript "nftables-agent-${name}-down" ''
                  ${pkgs.nftables}/bin/nft delete table inet agent-${name} 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip rule del fwmark ${toString fwmark} table ${toString fwmark} 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip route del default dev ${tunName} table ${toString fwmark} 2>/dev/null || true
                '';
              };
            };
          }
        ) tailscaleAgents
      ) ++ [{
        # Install the wrapper into each agent's PATH via /home/agent-{name}/bin
        agent-tailscale-wrappers = {
        description = "Install tailscale CLI wrappers into agent home directories";

        wantedBy = [ "agent-tailscale.target" ];
        after = [
          (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
        ];
        requires = [
          (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
        ];

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
                socketPath = "/run/tailscale/tailscaled-agent-${name}.socket";
              in
              ''
                mkdir -p /home/${username}/bin
                cat > /home/${username}/bin/tailscale <<'WRAPPER'
                #!/bin/sh
                exec ${pkgs.tailscale}/bin/tailscale --socket=${socketPath} "$@"
                WRAPPER
                chmod +x /home/${username}/bin/tailscale
                chown -R ${username}:agents /home/${username}/bin
              ''
            ) tailscaleAgents
          )}
        '';
        };
      }]);
    })

    # SSH agent configuration (ssh-agent + git signing + agenix secrets)
    (mkIf hasSshAgents {
      # Enable OpenSSH
      services.openssh.enable = true;

      # NOTE: Consumer (nixos-config) must declare agenix secrets:
      #   age.secrets."agent-{name}-ssh-key" = { file = ...; owner = "agent-{name}"; mode = "0400"; };
      #   age.secrets."agent-{name}-ssh-passphrase" = { file = ...; owner = "agent-{name}"; mode = "0400"; };

      # ssh-agent + git-config systemd services per SSH-enabled agent
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            sshKeyPath = "/run/agenix/${username}-ssh-key";
            sshPassphrasePath = "/run/agenix/${username}-ssh-passphrase";
            homesService =
              if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service";
            # Script that outputs the passphrase for SSH_ASKPASS
            askpassScript = pkgs.writeShellScript "ssh-askpass-${username}" ''
              ${pkgs.coreutils}/bin/cat ${sshPassphrasePath}
            '';
            # Script to add the key to the running ssh-agent
            addKeyScript = pkgs.writeShellScript "ssh-add-key-${username}" ''
              # Wait for the ssh-agent socket to be ready
              for i in $(seq 1 50); do
                [ -S "/run/ssh-agent-${username}/agent.sock" ] && break
                sleep 0.1
              done
              export SSH_AUTH_SOCK="/run/ssh-agent-${username}/agent.sock"
              export SSH_ASKPASS="${askpassScript}"
              export SSH_ASKPASS_REQUIRE="force"
              export DISPLAY="none"
              ${pkgs.openssh}/bin/ssh-add ${sshKeyPath}
            '';
          in
          {
            # ssh-agent daemon (foreground mode with -D)
            "ssh-agent-${username}" = {
              description = "SSH agent for ${username}";

              wantedBy = [ "multi-user.target" ];
              after = [
                "multi-user.target"
                homesService
              ];
              requires = [ homesService ];

              environment = {
                SSH_AUTH_SOCK = "/run/ssh-agent-${username}/agent.sock";
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                RuntimeDirectory = "ssh-agent-${username}";
                RuntimeDirectoryMode = "0700";
                ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a /run/ssh-agent-${username}/agent.sock";
                ExecStartPost = "${addKeyScript}";
                Restart = "always";
                RestartSec = 5;
              };
            };

            # Git SSH signing configuration
            "git-config-${username}" = {
              description = "Configure git SSH signing for ${username}";

              wantedBy = [ "multi-user.target" ];
              after = [ homesService ];
              requires = [ homesService ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = username;
                Group = "agents";
              };

              script = ''
                ${pkgs.git}/bin/git config --global gpg.format ssh
                ${pkgs.git}/bin/git config --global user.signingkey "${sshKeyPath}"
                ${pkgs.git}/bin/git config --global commit.gpgsign true
                ${pkgs.git}/bin/git config --global tag.gpgsign true
                ${pkgs.git}/bin/git config --global user.name "${agentCfg.fullName}"
                ${optionalString (agentCfg.email != null) ''
                  ${pkgs.git}/bin/git config --global user.email "${agentCfg.email}"
                ''}
              '';
            };
          }
        ) sshAgents
      );
    })
  ]);
}
