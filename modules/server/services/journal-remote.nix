# Keystone Journal Remote DNS Registration
#
# Registers the `journal.<domain>` DNS record when systemd-journal-remote is
# active on this host. journal-remote now serves HTTPS directly (no nginx
# proxy in the data path), so only the DNS A record is needed here.
#
# See conventions/tool.journal-remote.md
# See specs/REQ-020-journal-remote/requirements.md
{
  lib,
  config,
  ...
}:
let
  serverCfg = config.keystone.server;
  domain = config.keystone.domain;
  journalRemoteActive = config.services.journald.remote.enable;
in
{
  config =
    lib.mkIf
      (serverCfg.enable && journalRemoteActive && domain != null && serverCfg.tailscaleIP != null)
      {
        # Register a DNS A record for journal.<domain> so that upload clients can
        # resolve the journal-remote endpoint. No nginx vhost is created — HTTPS is
        # terminated directly by systemd-journal-remote using the ACME wildcard cert.
        keystone.server.generatedDNSRecords = [
          {
            name = "journal.${domain}";
            type = "A";
            value = serverCfg.tailscaleIP;
          }
        ];
      };
}
