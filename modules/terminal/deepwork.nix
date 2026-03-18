# DeepWork job library integration for the terminal environment.
#
# Exposes the curated job library shipped with the DeepWork flake by setting
# DEEPWORK_ADDITIONAL_JOBS_FOLDERS to the Nix store path of the library/jobs
# directory.  This makes the library jobs discoverable in every deepwork MCP
# session — for both human users and OS agents — without copying anything into
# the user's home directory.
#
# The library/jobs derivation (pkgs.keystone.deepwork-library-jobs) is built
# from the deepwork flake input in the keystone overlay (flake.nix).
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
        Enable DeepWork job library integration.

        When enabled, sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to include the
        curated job library from the DeepWork flake, making those jobs
        available in all deepwork MCP sessions.
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    # Append the keystone-managed DeepWork library jobs to the additional job
    # folders search path.  This is a colon-delimited list of absolute paths
    # (see deepwork/src/deepwork/jobs/discovery.py).  The library jobs are
    # read-only Nix store paths — deepwork writes instances/runs into the
    # project's own .deepwork/jobs directory, not here.
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS = "${pkgs.keystone.deepwork-library-jobs}";
    };
  };
}
