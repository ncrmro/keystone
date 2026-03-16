# Keystone Terminal — Forgejo CLI
#
# Installs `fj` (forgejo-cli) and `tea` (Gitea/Forgejo CLI) when enabled.
# forgejo-cli handles admin and auth operations; tea covers daily workflow
# (PRs, issues, releases) that forgejo-cli doesn't support.
#
# When domain + username are set (bridged from keystone.services.git in
# users.nix and agents.nix), generates:
#   - ~/.config/tea/config.yml — tea login with SSH agent auth (default login)
#   - ~/.local/share/forgejo-cli/keys.json — SSH:port→HTTPS alias so fj
#     resolves the correct API URL from SSH git remotes
#
# After deployment, fj still needs a one-time `fj -H <domain> auth login`
# to obtain an API token. The keys.json alias ensures subsequent commands
# infer the correct HTTPS host from SSH remotes.
#
# Auto-enabled via keystone.services.git.host in users.nix and agents.nix
# home-manager bridges.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.keystone.terminal;
  forgejoCfg = cfg.git.forgejo;
  hasDomainAndUser = forgejoCfg.domain != null && forgejoCfg.username != null;
  sshPortStr = toString forgejoCfg.sshPort;
in {
  options.keystone.terminal.git.forgejo = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Install forgejo-cli (fj) for Forgejo server interaction";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "git.ncrmro.com";
      description = "FQDN of the Forgejo instance. When set, generates tea and fj config.";
    };

    sshPort = mkOption {
      type = types.port;
      default = 2222;
      description = "SSH port for git operations on the Forgejo instance.";
    };

    username = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ncrmro";
      description = "Forgejo username for tea login.";
    };
  };

  config = mkIf (cfg.enable && forgejoCfg.enable) (mkMerge [
    {
      home.packages = [
        pkgs.forgejo-cli
        # tea provides repo/issue/PR operations that forgejo-cli lacks (e.g. tea pr create,
        # tea issue list). forgejo-cli focuses on admin/auth; tea covers the daily workflow.
        pkgs.tea
        pkgs.keystone.fetch-forgejo-sources
      ];
    }

    (mkIf hasDomainAndUser {
      # tea config — SSH agent auth, marked as default login so tea doesn't
      # prompt "falling back to login 'forgejo'?" on every invocation.
      home.file.".config/tea/config.yml".text = ''
        logins:
            - name: forgejo
              url: https://${forgejoCfg.domain}
              token: ""
              default: true
              ssh_host: ${forgejoCfg.domain}
              ssh_key: ~/.ssh/id_ed25519
              ssh_agent: true
              version_check: false
              user: ${forgejoCfg.username}
        preferences:
            editor: false
            flag_defaults:
                remote: ""
      '';

      # fj (forgejo-cli) config — alias SSH host:port to HTTPS host so fj
      # resolves the correct API URL from git remotes like
      # ssh://forgejo@git.ncrmro.com:2222/owner/repo.git
      # Without this alias, fj tries https://git.ncrmro.com:2222 (wrong port).
      #
      # Uses activation script (not home.file) because fj needs to write tokens
      # to this file via `fj auth add-key`. Seeds the alias on first run;
      # merges it into existing config on subsequent activations to preserve
      # user-added tokens.
      home.activation.forgejoCliConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        FJ_DIR="$HOME/.local/share/forgejo-cli"
        FJ_FILE="$FJ_DIR/keys.json"
        mkdir -p "$FJ_DIR"
        if [ ! -f "$FJ_FILE" ]; then
          cat > "$FJ_FILE" << 'SEED'
        ${builtins.toJSON {
          hosts = {};
          aliases = {
            "${forgejoCfg.domain}:${sshPortStr}" = forgejoCfg.domain;
          };
          default_ssh = [];
        }}
        SEED
        else
          # Merge alias into existing config, preserving tokens in hosts
          ${pkgs.jq}/bin/jq --arg key "${forgejoCfg.domain}:${sshPortStr}" \
            --arg val "${forgejoCfg.domain}" \
            '.aliases[$key] = $val' "$FJ_FILE" > "$FJ_FILE.tmp" \
            && mv "$FJ_FILE.tmp" "$FJ_FILE"
        fi
      '';
    })
  ]);
}
