# Keystone Terminal Mail (Himalaya)
#
# This module provides himalaya email client configuration.
# When enabled with a host configured, it generates a full config.toml.
#
# ## Stalwart (self-hosted) Example
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
# ## Gmail Example
#
# Requires an App Password (Google Account > Security > 2-Step Verification > App passwords).
# Store it in rbw: `rbw add gmail-app-password`
#
# ```nix
# keystone.terminal.mail = {
#   enable = true;
#   accountName = "gmail";
#   email = "user@gmail.com";
#   displayName = "User Name";
#   login = "user@gmail.com";  # Gmail uses full email as login
#   host = "imap.gmail.com";
#   passwordCommand = "rbw get gmail-app-password";
#   smtp = { host = "smtp.gmail.com"; port = 465; encryption = "tls"; };
#   folders = {
#     sent = "[Gmail]/Sent Mail";
#     drafts = "[Gmail]/Drafts";
#     trash = "[Gmail]/Trash";
#   };
# };
# ```
#
# ## iCloud Example
#
# Requires an App-Specific Password (appleid.apple.com > Security > App-Specific Passwords).
# Store it in rbw: `rbw add icloud-app-password`
#
# ```nix
# keystone.terminal.mail = {
#   enable = true;
#   accountName = "icloud";
#   email = "user@icloud.com";
#   displayName = "User Name";
#   login = "user@icloud.com";
#   host = "imap.mail.me.com";
#   passwordCommand = "rbw get icloud-app-password";
#   smtp = { host = "smtp.mail.me.com"; port = 587; encryption = "start-tls"; };
#   folders = {
#     sent = "Sent Messages";
#     drafts = "Drafts";
#     trash = "Deleted Messages";
#   };
# };
# ```
#
# ## Authentication Note
#
# For Stalwart, the login username is the account **name** (e.g. "ncrmro"),
# NOT the email address. For Gmail and iCloud, use the full email address.
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
      host = mkOption {
        type = types.str;
        default = "";
        description = "SMTP hostname (defaults to imap host when empty)";
      };

      port = mkOption {
        type = types.int;
        default = 465;
        description = "SMTP port (465 for TLS, 587 for STARTTLS)";
      };

      encryption = mkOption {
        type = types.enum [ "tls" "start-tls" "none" ];
        default = "tls";
        description = "SMTP encryption type: tls (port 465), start-tls (port 587), or none";
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
        message.send.backend.host = "${if cfg.smtp.host != "" then cfg.smtp.host else cfg.host}"
        message.send.backend.port = ${toString cfg.smtp.port}
        message.send.backend.encryption.type = "${cfg.smtp.encryption}"
        message.send.backend.login = "${cfg.login}"
        message.send.backend.auth.type = "password"
        message.send.backend.auth.command = "${cfg.passwordCommand}"

        folder.aliases.sent = "${cfg.folders.sent}"
        folder.aliases.drafts = "${cfg.folders.drafts}"
        folder.aliases.trash = "${cfg.folders.trash}"
      '';
    };
  };
}
