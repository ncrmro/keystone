# Keystone Terminal Contacts (Cardamum)
#
# This module provides cardamum (Pimalaya CardDAV CLI) configuration.
# When enabled with a host configured, it generates a cardamum config.toml
# that connects to Stalwart's CardDAV endpoint.
#
# Credentials default from the mail module — if mail is already configured,
# only `contacts.enable = true` is needed.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.contacts = {
#   enable = true;
#   # All other options auto-default from keystone.terminal.mail
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
  cfg = config.keystone.terminal.contacts;
  mailCfg = config.keystone.terminal.mail;
in
{
  options.keystone.terminal.contacts = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable contacts CLI tools (cardamum)";
    };

    accountName = mkOption {
      type = types.str;
      default = mailCfg.accountName;
      description = "Account name in Cardamum config";
    };

    host = mkOption {
      type = types.str;
      default = mailCfg.host;
      description = "CardDAV server hostname (defaults to mail host)";
    };

    login = mkOption {
      type = types.str;
      default = mailCfg.login;
      description = "CardDAV username (defaults to mail login)";
    };

    passwordCommand = mkOption {
      type = types.str;
      default = mailCfg.passwordCommand;
      description = "Command to retrieve the password (defaults to mail passwordCommand)";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.cardamum
    ];

    # Generate cardamum config only when host is configured
    xdg.configFile."cardamum/config.toml" = mkIf (cfg.host != "") {
      text = ''
        [accounts.${cfg.accountName}]
        default = true

        # Use direct home-uri instead of discovery — same nginx PROPFIND issue
        # as CalDAV (see calendar.nix). Stalwart CardDAV lives at /dav/card.
        carddav.home-uri = "https://${cfg.host}/dav/card"
        carddav.auth.basic.username = "${cfg.login}"
        carddav.auth.basic.password.command = ["sh", "-c", "${cfg.passwordCommand}"]
      '';
    };
  };
}
