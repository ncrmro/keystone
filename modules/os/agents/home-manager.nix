# Home-manager terminal integration for agents.
# NOTE: This must be a separate mkMerge entry, not merged with // into the
# mkIf block above. Using // on a mkIf value silently drops the merged keys
# because the module system only reads the mkIf's `content` attribute.
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg cfg topDomain agentPublicKey allKeysForAgent;
in
{
  config = optionalAttrs (options ? home-manager) {
    home-manager = mkIf (osCfg.enable && cfg != {} && any (a: a.terminal.enable) (attrValues cfg)) {
      users = mapAttrs' (name: agentCfg:
        let
          username = "agent-${name}";
        in
        nameValuePair username ({ pkgs, ... }: {
          imports = [ ../../terminal/default.nix ];

          # Provide empty keystoneInputs — editor.nix uses it for optional
          # unstable helix and kinda-nvim theme, both degrade gracefully to
          # stable defaults when the attrs are absent.
          _module.args.keystoneInputs = {};

          keystone.terminal = mkIf agentCfg.terminal.enable {
            enable = mkDefault true;
            git = let
              pubKey = agentPublicKey name;
            in {
              userName = mkDefault agentCfg.fullName;
              userEmail = mkDefault (if agentCfg.email != null
                then agentCfg.email
                else "${username}@${if topDomain != null then topDomain else "localhost"}");
              # Bridge SSH keys from keystone.keys for allowed_signers + signing
              sshPublicKeys = mkDefault (allKeysForAgent name);
              signingKey = mkDefault (
                if pubKey != null then "key::${pubKey}" else "~/.ssh/id_ed25519"
              );
              forgejo = {
                enable = mkDefault (config.keystone.services.git.host != null);
                domain = mkDefault config.keystone.services.git.domain;
                sshPort = mkDefault config.keystone.services.git.sshPort;
                # Use agent's Forgejo username, not the system username
                username = mkDefault agentCfg.git.username;
              };
            };
            mail = {
              enable = mkDefault true;
              accountName = mkDefault name;
              email = mkDefault (if agentCfg.mail.address != null
                then agentCfg.mail.address
                else "${username}@${if topDomain != null then topDomain else "localhost"}");
              displayName = mkDefault agentCfg.fullName;
              login = mkDefault username;
              host = mkDefault (if topDomain != null then "mail.${topDomain}" else "");
              # CRITICAL: agenix secrets and most editors add a trailing newline.
              # Stalwart rejects passwords with trailing whitespace, so we must
              # strip it. Without this, IMAP/SMTP auth fails.
              # tr is available via the agent's home-manager profile PATH (coreutils).
              passwordCommand = mkDefault "tr -d '\\n' < /run/agenix/agent-${name}-mail-password";
              imap.port = mkDefault agentCfg.mail.imap.port;
              smtp.port = mkDefault agentCfg.mail.smtp.port;
            };
            calendar = {
              enable = mkDefault true;
              # All credentials auto-derived from mail config above
            };
            contacts = {
              enable = mkDefault true;
              # All credentials auto-derived from mail config above
            };
            secrets = {
              enable = mkDefault true;
              email = mkDefault (if agentCfg.email != null
                then agentCfg.email
                else "${username}@${if topDomain != null then topDomain else "localhost"}");
              baseUrl = mkDefault (if topDomain != null then "https://vaultwarden.${topDomain}" else "");
              # Agents are unattended — use a custom pinentry that reads the master
              # password from the agenix secret instead of prompting interactively.
              pinentry = pkgs.writeShellScriptBin "rbw-pinentry-agenix" ''
                echo "OK Pleased to meet you"
                while IFS= read -r line; do
                  case "$line" in
                    GETPIN)
                      printf "D %s\n" "$(tr -d '\n' < /run/agenix/agent-${name}-bitwarden-password)"
                      echo "OK"
                      ;;
                    BYE)
                      echo "OK closing connection"
                      exit 0
                      ;;
                    *)
                      echo "OK"
                      ;;
                  esac
                done
              '';
            };
          };

          home.stateVersion = config.system.stateVersion;
        })
      ) (filterAttrs (_: a: a.terminal.enable) cfg);
    };
  };
}
