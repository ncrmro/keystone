# DeepWork job integration for the terminal environment.
#
# Sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to the Nix store path of
# pkgs.keystone.deepwork-keystone-jobs — a curated set of job definitions
# maintained in modules/terminal/deepwork-jobs/.  Only jobs that are
# explicitly listed in that derivation are included; no jobs are pulled in
# automatically from the upstream deepwork library.
#
# To add a new job:
#   1. Create modules/terminal/deepwork-jobs/<job-name>/ with job.yml + steps/
#   2. Add a `cp -r ... $out/` line in the deepwork-keystone-jobs derivation
#      inside the keystone overlay (flake.nix).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.deepwork;
in
{
  options.keystone.terminal.deepwork = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable DeepWork job integration.

        When enabled, sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to the keystone
        managed job store path, making those jobs available in all deepwork
        MCP sessions for both human users and OS agents.
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    # Append the keystone-managed DeepWork jobs to the additional job folders
    # search path.  This is a colon-delimited list of absolute paths consumed
    # by deepwork's discovery module (see deepwork/src/deepwork/jobs/discovery.py).
    # The store path is read-only; deepwork writes instances/runs into the
    # project's own .deepwork/jobs directory.
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS = "${pkgs.keystone.deepwork-keystone-jobs}";
    };
  };
}
