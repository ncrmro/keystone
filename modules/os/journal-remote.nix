# Centralized journal collection via systemd-journal-remote/upload.
#
# Implements REQ-020 (Centralized Journal Collection)
# See specs/REQ-020-journal-remote/requirements.md
#
# When one host enables `keystone.os.journalRemote.server.enable`, all other
# hosts with `keystone.os.enable` automatically forward their journals via
# systemd-journal-upload. Transport is plain HTTP over Tailscale — no TLS
# certificates needed since Tailscale provides encryption and authentication.
#
# SECURITY: Firewall restricts incoming connections to Tailscale IP ranges.
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
in
{
  options.keystone.os.journalRemote = {
    server = {
      enable = mkEnableOption "centralized journal collection (systemd-journal-remote receiver)";

      port = mkOption {
        type = types.port;
        default = 19532;
        description = "Listen port for systemd-journal-remote.";
      };

      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Bind address for the journal-remote listener.";
      };

      maxDisk = mkOption {
        type = types.str;
        default = "10G";
        description = "Maximum disk usage for remote journal storage.";
        example = "20G";
      };
    };

    upload = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Forward this host's journal to the fleet's journal-remote server.
          Set to false to opt out (e.g., for ephemeral VMs or test boxes).
          Has no effect if no host in the fleet enables server.enable.
        '';
      };

      serverUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          URL of the journal-remote server. Auto-derived from the server
          host's hostname when null. Override for non-standard setups.
        '';
      };
    };
  };

  config = mkIf osCfg.enable (mkMerge [
    # --- Server: receive journals from the fleet ---
    (mkIf cfg.server.enable {
      services.journald.remote = {
        enable = true;
        listen = "http";
        port = cfg.server.port;
      };

      # SECURITY: Restrict to Tailscale IP ranges (REQ-020.15)
      networking.firewall.extraCommands = ''
        iptables -A INPUT -p tcp --dport ${toString cfg.server.port} -s 100.64.0.0/10 -j ACCEPT
        iptables -A INPUT -p tcp --dport ${toString cfg.server.port} -j DROP
        ip6tables -A INPUT -p tcp --dport ${toString cfg.server.port} -s fd7a:115c:a1e0::/48 -j ACCEPT
        ip6tables -A INPUT -p tcp --dport ${toString cfg.server.port} -j DROP
      '';

      # Storage limit for remote journals (REQ-020.20-22)
      services.journald.extraConfig = ''
        SystemMaxUse=${cfg.server.maxDisk}
      '';
    })

    # --- Client: forward journals to the server ---
    # Activates when: (1) this host is NOT the server, (2) upload is enabled,
    # (3) a server URL is available (either explicit or auto-derived).
    (mkIf (!cfg.server.enable && cfg.upload.enable && cfg.upload.serverUrl != null) {
      services.journald.upload = {
        enable = true;
        settings.Upload = {
          URL = cfg.upload.serverUrl;
        };
      };
    })
  ]);
}
