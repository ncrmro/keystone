# Keystone Terminal Calendar (Calendula)
#
# This module provides calendula (Pimalaya CalDAV CLI) configuration.
# When enabled with either a host or url configured, it generates
# calendula/config.toml that connects to a CalDAV endpoint.
#
# Credentials default from the mail module — if mail is already configured,
# only `calendar.enable = true` is needed for Stalwart.
#
# ## Stalwart (self-hosted) Example
#
# ```nix
# keystone.terminal.calendar = {
#   enable = true;
#   # All other options auto-default from keystone.terminal.mail
# };
# ```
#
# ## iCloud Example
#
# Uses the same App-Specific Password as iCloud mail.
#
# ```nix
# keystone.terminal.calendar = {
#   enable = true;
#   accountName = "icloud";
#   url = "https://caldav.icloud.com";
#   login = "user@icloud.com";
#   passwordCommand = "rbw get icloud-app-password";
# };
# ```
#
# ## Gmail Note
#
# Google Calendar's CalDAV endpoint requires OAuth2 — basic auth (App Password)
# is not supported. Use Google Calendar's web interface or a dedicated OAuth2
# client instead.
#
# ## Explicit Configuration
#
# ```nix
# keystone.terminal.calendar = {
#   enable = true;
#   accountName = "personal";
#   host = "mail.example.com";
#   login = "me";
#   passwordCommand = "cat /run/agenix/mail-password";
# };
# ```
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.calendar;
  mailCfg = config.keystone.terminal.mail;
in
{
  options.keystone.terminal.calendar = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable calendar CLI tools (calendula)";
    };

    accountName = mkOption {
      type = types.str;
      default = mailCfg.accountName;
      description = "Account name in Calendula config";
    };

    host = mkOption {
      type = types.str;
      default = mailCfg.host;
      description = "CalDAV server hostname (defaults to mail host)";
    };

    login = mkOption {
      type = types.str;
      default = mailCfg.login;
      description = "CalDAV username (defaults to mail login)";
    };

    passwordCommand = mkOption {
      type = types.str;
      default = mailCfg.passwordCommand;
      description = "Command to retrieve the password (defaults to mail passwordCommand)";
    };

    url = mkOption {
      type = types.str;
      default = "";
      description = ''
        CalDAV home URI. When empty, defaults to https://{host}/dav/cal (Stalwart).
        Set explicitly for external providers:
          iCloud: https://caldav.icloud.com
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.calendula
    ];

    # Generate calendula.toml only when host or url is configured
    xdg.configFile."calendula/config.toml" = mkIf (cfg.host != "" || cfg.url != "") {
      text =
        let
          # Use explicit url if set; otherwise build Stalwart's default path.
          # Stalwart's /.well-known/caldav redirects to /dav/cal, but calendula's
          # discovery PROPFIND to the root URL gets a 400 from nginx before the
          # redirect — so we use the direct path instead of discovery.
          calDavUri = if cfg.url != "" then cfg.url else "https://${cfg.host}/dav/cal";
        in
        ''
          [accounts.${cfg.accountName}]
          default = true

          caldav.home-uri = "${calDavUri}"
          caldav.auth.basic.username = "${cfg.login}"
          caldav.auth.basic.password.command = ["sh", "-c", "${cfg.passwordCommand}"]
        '';
    };
  };
}
