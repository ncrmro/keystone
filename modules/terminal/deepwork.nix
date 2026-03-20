# DeepWork job integration for the terminal environment.
#
# Sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to a curated selection of jobs from
# the deepwork flake's library/jobs directory (pkgs.keystone.deepwork-library-jobs).
# Jobs are explicitly listed in the derivation in flake.nix — no jobs are
# included automatically.  To add a new job, add a cp -r entry in the
# deepwork-library-jobs runCommand once the job exists in the upstream repo.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.terminal.deepwork;
in {
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
    # Append the keystone-curated DeepWork library jobs to the additional job
    # folders search path.  This is a colon-delimited list of absolute paths
    # consumed by deepwork's discovery module.  The store path is read-only;
    # deepwork writes instances/runs into the project's own .deepwork/jobs.
    # Colon-delimited list of directories consumed by deepwork's discovery module.
    # 1. Upstream library jobs (curated from deepwork flake)
    # 2. Keystone-native jobs (consolidated from agent/notes repos)
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS = builtins.concatStringsSep ":" [
        "${pkgs.keystone.deepwork-library-jobs}"
        "${pkgs.keystone.keystone-deepwork-jobs}"
      ];
    };
  };
}
