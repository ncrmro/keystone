# DeepWork job integration for the terminal environment.
#
# Sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to discover jobs from three sources:
# 1. Writable deepwork repo checkout at ~/.keystone/repos/Unsupervisedcom/deepwork
#    (cloned by `ks update --pull`, enables `deepwork_jobs/learn` to write improvements)
# 2. Curated upstream library jobs from the deepwork flake (read-only Nix store fallback)
# 3. Keystone-native jobs from .deepwork/jobs/ in this repo
#
# The writable path is listed first — deepwork discovers jobs from the first match,
# so the local checkout takes precedence when present. Non-existent paths are skipped.
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
  # Cloned by `ks update --pull` to ~/.keystone/repos/Unsupervisedcom/deepwork.
  # Non-existent paths are silently skipped by deepwork's discovery module.
  deepworkRepoJobsPath = "${config.home.homeDirectory}/.keystone/repos/Unsupervisedcom/deepwork/library/jobs";
in
{
  options.keystone.terminal.deepwork = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable DeepWork job integration.

        When enabled, sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS so that jobs are
        discovered from the writable deepwork repo checkout (if cloned),
        the upstream library (Nix store fallback), and keystone-native jobs.
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    # Colon-delimited list of directories consumed by deepwork's discovery module.
    # 1. Writable deepwork checkout (enables deepwork_jobs/learn to modify library jobs)
    # 2. Upstream library jobs (read-only Nix store — curated from deepwork flake)
    # 3. Keystone-native jobs (consolidated from agent/notes repos)
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS = builtins.concatStringsSep ":" [
        deepworkRepoJobsPath
        "${pkgs.keystone.deepwork-library-jobs}"
        "${pkgs.keystone.keystone-deepwork-jobs}"
      ];
    };
  };
}
