# Keystone Journal Remote Nginx Proxy
#
# Auto-registers an nginx virtual host for systemd-journal-remote when the
# server module and journal-remote are both active. This provides HTTPS
# termination via the ACME wildcard certificate, with access restricted to
# the Tailscale network.
#
# Default subdomain: journal
# Backend port: from services.journald.remote.port (default 19532)
# Default access: tailscale
#
{
  lib,
  config,
  ...
}:
let
  serverCfg = config.keystone.server;

  # Detect whether systemd-journal-remote is active on this host.
  # This is set by modules/os/journal-remote.nix when the host is the journal server.
  journalRemoteActive = config.services.journald.remote.enable;
  journalRemotePort = config.services.journald.remote.port;
in
{
  config = lib.mkIf (serverCfg.enable && journalRemoteActive) {
    keystone.server._enabledServices.journalRemote = {
      subdomain = "journal";
      port = journalRemotePort;
      access = "tailscale";
      maxBodySize = null;
      websockets = false;
      registerDNS = true;
    };
  };
}
