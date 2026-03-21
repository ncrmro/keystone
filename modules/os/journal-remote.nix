# Centralized journal collection via systemd-journal-remote/upload.
#
# Implements REQ-020 (Centralized Journal Collection)
# See specs/REQ-020-journal-remote/requirements.md
#
# Configuration is auto-derived from keystone.hosts: the host with
# `journalRemote = true` becomes the server, all other hosts auto-forward
# via systemd-journal-upload. No per-host config needed in nixos-config.
#
# SECURITY: Firewall restricts journal-remote port to the Tailscale interface.
{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.os.journalRemote;
  osCfg = config.keystone.os;
  hostname = config.networking.hostName;

  # Auto-derive serverHost from keystone.hosts registry.
  # Find the host entry with journalRemote = true.
  journalRemoteHosts = filterAttrs (_: h: h.journalRemote or false) config.keystone.hosts;
  journalRemoteHostNames = attrNames journalRemoteHosts;
  derivedServerHost =
    if journalRemoteHostNames != [ ] then
      (builtins.getAttr (builtins.head journalRemoteHostNames) journalRemoteHosts).hostname
    else
      null;

  # Effective serverHost: explicit override > auto-derived from hosts registry
  effectiveServerHost = if cfg.serverHost != null then cfg.serverHost else derivedServerHost;

  # Derive the server URL from the serverHost hostname.
  # Bare hostnames resolve via Tailscale MagicDNS.
  derivedServerUrl =
    if effectiveServerHost != null then
      "http://${effectiveServerHost}:${toString cfg.server.port}"
    else
      null;

  # Effective server URL: explicit override > auto-derived from serverHost
  effectiveServerUrl =
    if cfg.upload.serverUrl != null then cfg.upload.serverUrl else derivedServerUrl;

  # Is this host the journal server?
  isServer = effectiveServerHost == hostname;

  # Should this host upload? Only if: not the server, upload enabled, and a URL exists.
  shouldUpload = !isServer && cfg.upload.enable && effectiveServerUrl != null;
in
{
  options.keystone.os.journalRemote = {
    serverHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Hostname of the journal-remote server. Auto-derived from keystone.hosts
        (the host with journalRemote = true). Override only for non-standard setups.
        When null and no host has journalRemote = true, journal forwarding is disabled.
      '';
      example = "ocean";
    };

    server = {
      enable = mkEnableOption "centralized journal collection (systemd-journal-remote receiver)";

      port = mkOption {
        type = types.port;
        default = 19532;
        description = "Listen port for systemd-journal-remote.";
      };
    };

    upload = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Forward this host's journal to the fleet's journal-remote server.
          Set to false to opt out (e.g., for ephemeral VMs or test boxes).
          Has no effect if no serverHost is configured.
        '';
      };

      serverUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          URL of the journal-remote server. Auto-derived from serverHost
          when null. Override for non-standard setups.
        '';
      };
    };
  };

  config = mkIf osCfg.enable (mkMerge [
    # --- Auto-derive server.enable from hosts registry ---
    (mkIf isServer {
      keystone.os.journalRemote.server.enable = mkDefault true;
    })

    # --- Assertions and warnings ---
    {
      assertions = [
        {
          # Only one host in keystone.hosts should have journalRemote = true
          assertion = length journalRemoteHostNames <= 1;
          message = ''
            keystone.hosts: multiple hosts have journalRemote = true: ${concatStringsSep ", " journalRemoteHostNames}.
            Exactly one host should be the journal-remote server.
          '';
        }
      ];

      warnings = optional (cfg.server.enable && effectiveServerHost == null) ''
        keystone.os.journalRemote: server.enable is true but no serverHost is configured
        and no host in keystone.hosts has journalRemote = true. Clients won't auto-discover
        this server. Set journalRemote = true on this host's entry in keystone.hosts.
      '';
    }

    # --- Server: receive journals from the fleet ---
    (mkIf isServer {
      services.journald.remote = {
        enable = true;
        listen = "http";
        port = cfg.server.port;
      };

      # SECURITY: Only accept connections on the Tailscale interface (REQ-020.15).
      # All keystone hosts run Tailscale, so this is sufficient to restrict access
      # to fleet members without fragile iptables rules.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.server.port ];
    })

    # --- Client: forward journals to the server ---
    # REQ-020.7: auto-forward when serverHost is set
    # REQ-020.9: skip if this host IS the server (no self-loop)
    # REQ-020.13: no-op when serverHost is null
    (mkIf shouldUpload {
      services.journald.upload = {
        enable = true;
        settings.Upload = {
          URL = effectiveServerUrl;
        };
      };
    })
  ]);
}
