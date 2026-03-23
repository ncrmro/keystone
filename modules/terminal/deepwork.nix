# DeepWork job integration for the terminal environment.
#
# Sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to a curated selection of jobs from
# the deepwork flake's library/jobs directory (pkgs.keystone.deepwork-library-jobs).
# Jobs are explicitly listed in the derivation in flake.nix — no jobs are
# included automatically.  To add a new job, add a cp -r entry in the
# deepwork-library-jobs runCommand once the job exists in the upstream repo.
#
# Dev mode (REQ-018): When keystone.terminal.devMode.keystonePath is set,
# keystone-deepwork-jobs points at the local checkout's .deepwork/jobs/ —
# editable in place without rebuilding. Upstream library jobs remain
# immutable store copies (they come from the deepwork flake, not keystone).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.deepwork;
  terminalCfg = config.keystone.terminal;
  devPath = terminalCfg.devMode.keystonePath;
  isDev = devPath != null;
in
{
  options.keystone.terminal.deepwork = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable DeepWork job integration.

        When enabled, sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to the curated
        selection of library jobs from the DeepWork flake, making them
        available in all deepwork MCP sessions for both human users and OS
        agents.
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    # Colon-delimited list of directories consumed by deepwork's discovery module.
    # 1. Upstream library jobs (curated from deepwork flake) — always from store
    # 2. Keystone-native jobs — local checkout in dev mode, store copy in locked mode
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS = builtins.concatStringsSep ":" [
        "${pkgs.keystone.deepwork-library-jobs}"
        (if isDev then "${devPath}/.deepwork/jobs" else "${pkgs.keystone.keystone-deepwork-jobs}")
      ];
    };
  };
}
