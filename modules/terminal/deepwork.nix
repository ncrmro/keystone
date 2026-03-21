# DeepWork job integration for the terminal environment.
#
# Two modes:
# - Normal (default): DEEPWORK_ADDITIONAL_JOBS_FOLDERS points at read-only
#   Nix store paths for upstream library jobs and keystone-native jobs.
# - Dev mode: DEEPWORK_ADDITIONAL_JOBS_FOLDERS points at the writable deepwork
#   repo checkout at ~/.keystone/repos/Unsupervisedcom/deepwork, enabling
#   deepwork_jobs/learn to write improvements to library jobs in place.
#   The checkout is managed by `ks update --pull`.
#
# Implements REQ-015 (REQ-015.3, REQ-015.10)
# Implements REQ-001 FR-014 (Host-Level Feature Flags — devMode pass-through)
# See conventions/process.deepwork-job.md
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.deepwork;
  termCfg = config.keystone.terminal;
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
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS =
        if termCfg.devMode then
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
