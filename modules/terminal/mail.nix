# Keystone Terminal Mail (Himalaya)
#
# This module provides himalaya email client configuration.
# When enabled with a host configured, it generates a full config.toml.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.mail = {
#   enable = true;
#   accountName = "personal";
#   email = "me@example.com";
#   displayName = "My Name";
#   login = "me";  # Stalwart account name, not email
#   host = "mail.example.com";
#   passwordCommand = "cat /run/agenix/mail-password";
# };
# ```
#
# ## Authentication Note
#
# When connecting with IMAP/SMTP to Stalwart, the login username is the
# Stalwart account **name** (e.g. "ncrmro"), NOT the email address.
# The email is only used as the envelope/from address.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.mail;
in
{
  options.keystone.terminal.mail = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable mail CLI tools (himalaya)";
    };

    accountName = mkOption {
      type = types.str;
      default = "";
      description = "Account name in Himalaya config";
    };

    email = mkOption {
      type = types.str;
      default = "";
      description = "Email address";
    };

    displayName = mkOption {
      type = types.str;
      default = "";
      description = "Display name for sent emails";
    };

    login = mkOption {
      type = types.str;
      default = "";
      description = "Stalwart account login name (not email address)";
    };

    passwordCommand = mkOption {
      type = types.str;
      default = "";
      description = "Command to retrieve the password";
    };

    host = mkOption {
      type = types.str;
      default = "";
      description = "Mail server hostname";
    };

    imap = {
      port = mkOption {
        type = types.int;
        default = 993;
        description = "IMAP port";
      };
    };

    smtp = {
      port = mkOption {
        type = types.int;
        default = 465;
        description = "SMTP port";
      };
    };

    folders = {
      sent = mkOption {
        type = types.str;
        default = "Sent Items";
        description = "Sent folder name (Stalwart default: 'Sent Items')";
      };

      drafts = mkOption {
        type = types.str;
        default = "Drafts";
        description = "Drafts folder name";
      };

      trash = mkOption {
        type = types.str;
        default = "Deleted Items";
        description = "Trash folder name (Stalwart default: 'Deleted Items')";
      };
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      # Himalaya - CLI to manage emails
      # https://github.com/pimalaya/himalaya
      # Provided via keystone overlay
      pkgs.keystone.himalaya
    ];

    # Generate config.toml only when host is configured
    xdg.configFile."himalaya/config.toml" = mkIf (cfg.host != "") {
      text = ''
        [accounts.${cfg.accountName}]
        email = "${cfg.email}"
        display-name = "${cfg.displayName}"
        default = true

        backend.type = "imap"
        backend.host = "${cfg.host}"
        backend.port = ${toString cfg.imap.port}
        backend.encryption.type = "tls"
        backend.login = "${cfg.login}"
        backend.auth.type = "password"
        backend.auth.command = "${cfg.passwordCommand}"

        message.send.backend.type = "smtp"
        message.send.backend.host = "${cfg.host}"
        message.send.backend.port = ${toString cfg.smtp.port}
        message.send.backend.encryption.type = "tls"
        message.send.backend.login = "${cfg.login}"
        message.send.backend.auth.type = "password"
        message.send.backend.auth.command = "${cfg.passwordCommand}"

        # Stalwart folder names (differ from Himalaya defaults)
        folder.aliases.sent = "${cfg.folders.sent}"
        folder.aliases.drafts = "${cfg.folders.drafts}"
        folder.aliases.trash = "${cfg.folders.trash}"
      '';
    };
  };
}
