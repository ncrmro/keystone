# Keystone OS 1Password Module
#
# Enables 1Password CLI and optional GUI with SSH agent integration at the
# system level. Complementary to keystone.terminal.onePassword which handles
# user-level shell/git/SSH agent wiring in home-manager.
#
# ## Quick start
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
# ## Notes
#
# - `programs._1password.enable` places `op` on PATH and sets the sticky-bit
#   so it can access the system keychain.
# - `programs._1password-gui.enable` installs the desktop app and
#   configures polkit so the browser extension and biometric unlock work.
# - The SSH agent socket (~/.1password/agent.sock) is managed entirely by the
#   running 1Password GUI; no systemd unit is needed here.
# - For user-level git signing and shell integration see
#   keystone.terminal.onePassword.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.onePassword;
in
{
  options.keystone.os.onePassword = {
    enable = mkEnableOption "1Password CLI system integration";

    gui = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable the 1Password GUI desktop application.  Required for:
          - SSH agent (`~/.1password/agent.sock`)
          - biometric (Touch ID / fingerprint) unlock
          - browser extension auto-fill
          - `op-ssh-sign` helper for git commit signing
        '';
      };

      polkitPolicyOwners = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Usernames that are allowed to use the 1Password system-level polkit
          integration (needed for the browser extension and biometric unlock).
          Passed directly to `programs._1password-gui.polkitPolicyOwners`.
        '';
        example = [
          "alice"
          "bob"
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    # CLI: installs `op` on PATH with correct setuid/sticky bits so that
    # the 1Password agent and system keychain work correctly.
    programs._1password.enable = true;

    # GUI (optional): installs the desktop app and op-ssh-sign helper.
    programs._1password-gui = mkIf cfg.gui.enable {
      enable = true;
      polkitPolicyOwners = cfg.gui.polkitPolicyOwners;
    };
  };
}
