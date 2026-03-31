# Keystone Services Registry
#
# Shared top-level options declaring which host runs each infrastructure service.
# Set once per infrastructure, consumed by multiple modules:
#
#   - modules/os/mail.nix: auto-enables Stalwart when hostName matches services.mail.host
#   - modules/os/git-server.nix: auto-enables Forgejo when hostName matches services.git.host
#   - modules/os/agents.nix: agentctl provision uses mail.host for secret recipients
#   - modules/os/users.nix: bridges forgejo.enable into home-manager when git.host is set
#   - modules/terminal/forgejo.nix: installs forgejo-cli when forgejo.enable is true
#
# Usage:
#   keystone.services = {
#     mail.host = "ocean";
#     git.host = "ocean";
#   };
{ lib, config, ... }:
with lib;
let
  cfg = config.keystone.services;
  hosts = config.keystone.hosts;
  hostNames = mapAttrsToList (_: h: h.hostname) hosts;
  validateHost =
    name: host:
    optional (host != null && hosts != { } && !elem host hostNames) {
      assertion = false;
      message = "keystone.services.${name}.host = \"${host}\" does not match any hostname in keystone.hosts. Valid hostnames: ${concatStringsSep ", " hostNames}";
    };

  # Resolve a hostname to its Headscale ACL identity
  resolveACLIdentity =
    hName:
    let
      hostEntry = findFirst (h: h.hostname == hName) null (attrValues hosts);
    in
    if hostEntry != null && hostEntry.headscaleIdentity != null then
      hostEntry.headscaleIdentity
    else
      hName;

  # Generate ACL rules for immich server <-> worker communication
  immichACLRules =
    let
      serverHost = cfg.immich.host;
      workers = cfg.immich.workers;
      serverIdentity = resolveACLIdentity serverHost;
      workerIdentities = map resolveACLIdentity workers;
    in
    optionals (serverHost != null && workers != [ ]) [
      {
        action = "accept";
        comment = "immich: server -> ML workers (inference)";
        src = [ serverIdentity ];
        dst = map (id: "${id}:3003") workerIdentities;
      }
    ];
in
{
  options.keystone.services = {
    mail.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ocean";
      description = ''
        The networking.hostName of the mail server.
        Auto-enables Stalwart on that host. Used by agentctl provision
        to determine mail-password secret recipients.
      '';
    };

    git.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ocean";
      description = ''
        The networking.hostName of the git server.
        Auto-enables Forgejo on that host. Used by terminal to install forgejo-cli.
      '';
    };

    git.domain = mkOption {
      type = types.nullOr types.str;
      default = if config.keystone.domain != null then "git.${config.keystone.domain}" else null;
      description = "FQDN of the Forgejo instance (e.g., git.ncrmro.com). Used by terminal/forgejo.nix to generate tea config.";
    };

    git.sshPort = mkOption {
      type = types.port;
      default = 2222;
      description = "SSH port for git operations on the Forgejo instance.";
    };

    immich.host = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "The networking.hostName of the primary Immich server.";
    };

    immich.workers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of hostnames acting as GPU/ML workers.";
    };

    generatedACLRules = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            action = mkOption {
              type = types.str;
              default = "accept";
            };
            comment = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            src = mkOption { type = types.listOf types.str; };
            dst = mkOption { type = types.listOf types.str; };
          };
        }
      );
      default = [ ];
      description = ''
        Auto-generated Headscale ACL rules from service topology.
        Consume on the headscale host via keystone.headscale.aclRules.
      '';
    };
  };

  config.keystone.services.generatedACLRules = immichACLRules;

  config.assertions =
    (validateHost "mail" cfg.mail.host)
    ++ (validateHost "git" cfg.git.host)
    ++ (validateHost "immich" cfg.immich.host)
    ++ (concatMap (h: validateHost "immich.workers" h) cfg.immich.workers);
}
