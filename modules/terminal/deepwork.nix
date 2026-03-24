# DeepWork job integration for the terminal environment.
#
# Sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to a curated selection of jobs from
# the deepwork flake's library/jobs directory (pkgs.keystone.deepwork-library-jobs).
# Jobs are explicitly listed in the derivation in flake.nix — no jobs are
# included automatically.  To add a new job, add a cp -r entry in the
# deepwork-library-jobs runCommand once the job exists in the upstream repo.
#
# Development mode (REQ-018): When keystone.terminal.development is true,
# both job sources swap to local checkouts derived from keystone.terminal.repos:
# - deepwork repo → library jobs from local checkout's library/jobs/
# - keystone repo → keystone-native jobs from local checkout's .deepwork/jobs/
# When development mode is off, all paths resolve to Nix store copies.
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
  isDev = terminalCfg.development;
  repos = terminalCfg.repos;
  homeDir = config.home.homeDirectory;

  # Look up a repo's local checkout path by its flakeInput name.
  repoPath =
    flakeInputName:
    let
      # 1. Try exact match by flakeInput attribute (primary lookup)
      # This works for auto-populated repos and manually mapped ones.
      entry = findFirst (name: (repos.${name}.flakeInput or null) == flakeInputName) null (
        attrNames repos
      );

      # 2. Fallback: if the repo entry itself is named like the flakeInputName
      # (e.g. name = "keystone" instead of "ncrmro/keystone")
      entryByName = if entry == null && repos ? ${flakeInputName} then flakeInputName else null;

      # 3. Fallback: find entry where the repo name (last part of owner/repo) matches the flakeInputName
      # This handles "ncrmro/keystone" when flakeInput is null but we know it's keystone.
      entryBySuffix =
        if entry == null && entryByName == null then
          findFirst (name: (last (splitString "/" name)) == flakeInputName) null (attrNames repos)
        else
          null;

      finalEntry =
        if entry != null then
          entry
        else if entryByName != null then
          entryByName
        else
          entryBySuffix;
    in
    if finalEntry != null then "${homeDir}/.keystone/repos/${finalEntry}" else null;

  keystonePath = repoPath "keystone";
  deepworkPath = repoPath "deepwork";
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
    # In dev mode both sources swap to local checkouts; in locked mode both use store.
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS = builtins.concatStringsSep ":" [
        (
          if isDev && deepworkPath != null then
            "${deepworkPath}/library/jobs"
          else
            "${pkgs.keystone.deepwork-library-jobs}"
        )
        (
          if isDev && keystonePath != null then
            "${keystonePath}/.deepwork/jobs"
          else
            "${pkgs.keystone.keystone-deepwork-jobs}"
        )
      ];
    };
  };
}
