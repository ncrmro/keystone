# DeepWork job integration for the terminal environment.
#
# Two modes:
# - Normal (default): DEEPWORK_ADDITIONAL_JOBS_FOLDERS points at read-only
#   Nix store paths for upstream library jobs and keystone-native jobs.
# - Dev mode: DEEPWORK_ADDITIONAL_JOBS_FOLDERS points at the writable deepwork
#   repo checkout at ~/.keystone/repos/Unsupervisedcom/deepwork, enabling
#   deepwork_jobs/learn to write improvements to library jobs in place.
#   The checkout is managed by `ks update --pull`.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.deepwork;
  # Writable deepwork checkout at the canonical keystone repos path.
  # Only used when devMode is enabled. Managed by `ks update --pull`.
  deepworkRepoJobsPath = "${config.home.homeDirectory}/.keystone/repos/Unsupervisedcom/deepwork/library/jobs";
in
{
  options.keystone.terminal.deepwork = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable DeepWork job integration.

        When enabled, sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to make upstream
        library jobs and keystone-native jobs available in all deepwork MCP
        sessions for both human users and OS agents.
      '';
    };

    devMode = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable DeepWork development mode.

        When enabled, DEEPWORK_ADDITIONAL_JOBS_FOLDERS points at the writable
        deepwork repo checkout at ~/.keystone/repos/Unsupervisedcom/deepwork
        instead of the read-only Nix store path. This enables deepwork_jobs/learn
        to modify upstream library jobs in place. The checkout is managed by
        `ks update --pull`.
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS =
        if cfg.devMode then
          # Dev mode: writable checkout for library jobs + keystone-native jobs
          builtins.concatStringsSep ":" [
            deepworkRepoJobsPath
            "${pkgs.keystone.keystone-deepwork-jobs}"
          ]
        else
          # Normal mode: read-only store paths
          builtins.concatStringsSep ":" [
            "${pkgs.keystone.deepwork-library-jobs}"
            "${pkgs.keystone.keystone-deepwork-jobs}"
          ];
    };
  };
}
