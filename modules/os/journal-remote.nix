# Centralized journal collection via systemd-journal-remote/upload.
#
# Implements REQ-020 (Centralized Journal Collection)
# See specs/REQ-020-journal-remote/requirements.md
#
# When one host enables `keystone.os.journalRemote.server.enable`, set
# `keystone.os.journalRemote.serverHost` in shared config so all other
# hosts auto-forward their journals via systemd-journal-upload. Transport
# is plain HTTP over Tailscale — no TLS certificates needed.
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

  # Derive the server URL from the serverHost hostname.
  # Bare hostnames resolve via Tailscale MagicDNS.
  derivedServerUrl =
    if cfg.serverHost != null then "http://${cfg.serverHost}:${toString cfg.server.port}" else null;

  # Effective server URL: explicit override > auto-derived from serverHost
  effectiveServerUrl =
    if cfg.upload.serverUrl != null then cfg.upload.serverUrl else derivedServerUrl;

  # Is this host the journal server?
  isServer = cfg.server.enable;

  # Should this host upload? Only if: not the server, upload enabled, and a URL exists.
  shouldUpload = !isServer && cfg.upload.enable && effectiveServerUrl != null;
in
{
  options.keystone.os.journalRemote = {
    serverHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Hostname of the journal-remote server. Set this in shared config
        (e.g., alongside keystone.domain) so all hosts know where to
        forward journals. Bare hostnames resolve via Tailscale MagicDNS.
        When null, journal forwarding is disabled fleet-wide.
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
          Has no effect if serverHost is null.
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
    # --- Assertions and warnings ---
    {
      assertions = [
        {
          # REQ-020.6: server.enable must only be set on the serverHost
          assertion = !cfg.server.enable || cfg.serverHost == hostname || cfg.serverHost == null;
          message = ''
            keystone.os.journalRemote: server.enable is true on ${hostname},
            but serverHost is set to "${toString cfg.serverHost}". The server
            must only be enabled on the host named in serverHost.
          '';
        }
      ];

      warnings = optional (cfg.server.enable && cfg.serverHost == null) ''
        keystone.os.journalRemote: server.enable is true but serverHost is null.
        Clients won't auto-discover this server. Set serverHost = "${hostname}"
        in shared config so other hosts know where to forward journals.
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
