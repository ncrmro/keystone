# Keystone Terminal 1Password Module
#
# Home-manager module providing user-level 1Password integration:
# - `op` CLI with shell completion
# - SSH agent via the 1Password app socket (~/.1password/agent.sock)
# - Git commit/tag signing via `op-ssh-sign`
#
# ## Prerequisites
#
# The 1Password GUI must be running on the machine so that the SSH agent
# socket is available.  Enable at the NixOS level:
#
# ```nix
# keystone.os.onePassword = {
#   enable = true;
#   gui = {
#     enable = true;
#     polkitPolicyOwners = [ "alice" ];
#   };
# };
# ```
#
# ## Quick start
#
# ```nix
# keystone.terminal.onePassword = {
#   enable = true;
# };
# ```
#
# ## What this module does
#
# When `enable = true`:
# 1. Adds `_1password-cli` (`op`) to the user's packages.
# 2. Sets `SSH_AUTH_SOCK` to `~/.1password/agent.sock` so the running
#    1Password app is used as the SSH agent (supersedes `ssh-agent`).
# 3. Adds `IdentityAgent ~/.1password/agent.sock` to `~/.ssh/config` for
#    tools that read the config directly.
# 4. Configures git to use `op-ssh-sign` for commit/tag signing when
#    `keystone.terminal.git.enable` is also true.
#
# ## Opting out of sub-features
#
# Each sub-feature can be disabled independently:
#
# ```nix
# keystone.terminal.onePassword = {
#   enable = true;
#   sshAgent.enable = false;    # keep op CLI but use default ssh-agent
#   gitSigning.enable = false;  # manage git signing separately
# };
# ```
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.onePassword;
  terminalCfg = config.keystone.terminal;
  opAgentSock = "${config.home.homeDirectory}/.1password/agent.sock";
in
{
  options.keystone.terminal.onePassword = {
    enable = mkEnableOption "1Password CLI and SSH agent integration";

    sshAgent = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Point SSH_AUTH_SOCK and the SSH client config at the 1Password SSH
          agent socket (~/.1password/agent.sock).  Requires the 1Password GUI
          to be running.
        '';
      };
    };

    gitSigning = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Configure git to use `op-ssh-sign` for commit and tag signing.
          Requires `keystone.terminal.git.enable = true` and the 1Password
          GUI package to be installed (provides `op-ssh-sign`).
        '';
      };

      opSshSignPath = mkOption {
        type = types.str;
        default = "${pkgs._1password-gui}/bin/op-ssh-sign";
        defaultText = literalExpression ''"''${pkgs._1password-gui}/bin/op-ssh-sign"'';
        description = ''
          Path to the `op-ssh-sign` helper.  Defaults to the binary shipped
          with the `_1password-gui` nixpkgs package.  Override if you install
          1Password through a different mechanism.
        '';
      };
    };
  };

  config = mkIf (terminalCfg.enable && cfg.enable) (
    mkMerge [
      # ── op CLI ──────────────────────────────────────────────────────────
      {
        home.packages = [ pkgs._1password-cli ];
      }

      # ── SSH agent ───────────────────────────────────────────────────────
      (mkIf cfg.sshAgent.enable {
        # Export SSH_AUTH_SOCK for interactive shells and user services.
        home.sessionVariables = {
          SSH_AUTH_SOCK = opAgentSock;
        };

        # Wire the SSH client so tools that parse ~/.ssh/config directly
        # (e.g. Helix file picker, some git remotes) also use the agent.
        programs.ssh = {
          enable = true;
          extraConfig = ''
            Host *
              IdentityAgent "${opAgentSock}"
          '';
        };
      })

      # ── Git signing ─────────────────────────────────────────────────────
      (mkIf (terminalCfg.git.enable && cfg.gitSigning.enable) {
        programs.git.settings = {
          gpg.ssh.program = mkDefault cfg.gitSigning.opSshSignPath;
        };
      })
    ]
  );
}
