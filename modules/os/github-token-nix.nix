# Keystone OS — GitHub token for the nix daemon.
#
# Materializes /etc/nix/access-tokens.conf from a root-readable agenix
# secret and `!include`s it into nix.conf so flake fetches (e.g.
# `nix flake update`, `ks update`) authenticate to GitHub and hit the
# 5000/hr authenticated rate ceiling instead of the 60/hr anonymous one.
#
# The token value never enters the Nix store: the secret stays in
# /run/agenix, and a systemd oneshot copies it into the include file at
# activation time.
#
# This is the OS-level counterpart to keystone.terminal.github (the
# user-PAT module). The user PAT is mode 0400 owner=<user> and serves
# `gh`/`git`; the nix-daemon runs as root and needs its own secret with
# system-key recipients. See conventions/tool.github-pats.md rule 26 and
# conventions/tool.nix.md for the os-level access-tokens convention.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.os.githubTokenNix;
  basename = baseNameOf cfg.tokenFile;
  # Accepted patterns (also documented in tool.nix.md):
  #   nix-flake-github-token             — portable, recommended default
  #   <hostname>-nix-flake-github-token  — host-scoped
  validBasename =
    basename == "nix-flake-github-token"
    || (
      lib.hasSuffix "-nix-flake-github-token" basename && builtins.match "[a-z0-9-]+" basename != null
    );
in
{
  options.keystone.os.githubTokenNix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Wire an agenix-decrypted GitHub token into /etc/nix/nix.conf via
        a root-readable include file, so the nix daemon uses the
        authenticated 5000/hr GitHub rate-limit ceiling for flake fetches.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/nix-flake-github-token";
      description = ''
        Path to the decrypted token file. The adopter is responsible for
        declaring an `age.secrets.<name>` entry that produces this file
        with `owner = "root"; mode = "0400";` and a recipient set drawn
        from system keys (not user keys).

        The basename SHOULD follow the convention
        `nix-flake-github-token` (portable) or
        `<hostname>-nix-flake-github-token` (host-scoped). See
        conventions/tool.nix.md.
      '';
    };

    includePath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nix/access-tokens.conf";
      description = ''
        Path of the include file the oneshot writes. Referenced from
        `nix.extraOptions` as `!include <path>`.
      '';
    };
  };

  config = lib.mkIf (config.keystone.os.enable && cfg.enable) {
    assertions = [
      {
        assertion = validBasename;
        message =
          "keystone.os.githubTokenNix.tokenFile basename '${basename}' does not match "
          + "the OS-level naming convention. Use 'nix-flake-github-token' (portable) "
          + "or '<hostname>-nix-flake-github-token' (host-scoped). See "
          + "conventions/tool.nix.md.";
      }
    ];

    systemd.services.nix-github-access-token = {
      description = "Materialize ${cfg.includePath} from ${cfg.tokenFile}";
      wantedBy = [ "multi-user.target" ];
      after = [ "agenix.service" ];
      requires = [ "agenix.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Hardening — write only to /etc/nix.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ (builtins.dirOf cfg.includePath) ];
        # /run/agenix is a tmpfs mount; PrivateTmp would shadow it.
        PrivateTmp = false;
      };

      script = ''
        set -eu
        if [ ! -s ${lib.escapeShellArg cfg.tokenFile} ]; then
          echo "nix-github-access-token: ${cfg.tokenFile} missing or empty" >&2
          exit 1
        fi
        umask 0137
        tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg (cfg.includePath + ".XXXXXX")})"
        trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
        {
          printf 'access-tokens = github.com=%s\n' \
            "$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg cfg.tokenFile})"
        } > "$tmp"
        ${pkgs.coreutils}/bin/chown root:root "$tmp"
        ${pkgs.coreutils}/bin/chmod 0640 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" ${lib.escapeShellArg cfg.includePath}
        trap - EXIT
      '';
    };

    nix.extraOptions = lib.mkAfter ''
      !include ${cfg.includePath}
    '';
  };
}
