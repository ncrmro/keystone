# Keystone Terminal Calendar (Calendula)
#
# This module provides calendula (Pimalaya CalDAV CLI) configuration.
# When enabled with a host configured, it generates a calendula.toml
# that connects to Stalwart's CalDAV endpoint.
#
# Credentials default from the mail module — if mail is already configured,
# only `calendar.enable = true` is needed.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.calendar = {
#   enable = true;
#   # All other options auto-default from keystone.terminal.mail
# };
# ```
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
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.calendula
    ];

    # Generate calendula.toml only when host is configured
    xdg.configFile."calendula/config.toml" = mkIf (cfg.host != "") {
      text = ''
        [accounts.${cfg.accountName}]
        default = true

        # Use direct home-uri instead of discovery — Stalwart's /.well-known/caldav
        # redirects to /dav/cal, but calendula's discovery PROPFIND to the root
        # URL gets a 400 from nginx before following the redirect.
        caldav.home-uri = "https://${cfg.host}/dav/cal"
        caldav.auth.basic.username = "${cfg.login}"
        caldav.auth.basic.password.command = ["sh", "-c", "${cfg.passwordCommand}"]
      '';
    };
  };
}
