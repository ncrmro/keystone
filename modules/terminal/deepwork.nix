# DeepWork job integration for the terminal environment.
#
# Sets DEEPWORK_ADDITIONAL_JOBS_FOLDERS to a curated selection of jobs from
# the deepwork flake's library/jobs directory (pkgs.keystone.deepwork-library-jobs).
# Jobs are explicitly listed in the derivation in flake.nix — no jobs are
# included automatically.  To add a new job, add a cp -r entry in the
# deepwork-library-jobs runCommand once the job exists in the upstream repo.
#
# Development mode (REQ-018): When keystone.development is true,
# both job sources swap to local checkouts derived from keystone.repos:
# - deepwork repo → library jobs from local checkout's library/jobs/
# - keystone repo → keystone-native jobs from local checkout's .deepwork/jobs/
# When development mode is off, all paths resolve to Nix store copies.
#
# Published vs internal jobs: only `.deepwork/jobs/` is packaged into
# pkgs.keystone.keystone-deepwork-jobs and reaches adopters. The sibling
# `.deepwork/jobs-internal/` directory holds keystone-development-only
# plumbing (contributor authoring tools like agent_builder, in-progress stubs)
# and is appended to the discovery path only in dev mode so contributors can
# still invoke it. Runtime jobs that adopter-installed code invokes (e.g.
# task_loop, called by modules/os/agents/scripts/task-loop.sh) MUST live in
# `.deepwork/jobs/`.
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
  isDev = config.keystone.development;
  isAgent = lib.hasPrefix "agent-" config.home.username;
  repos = config.keystone.repos;
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
    # The internal jobs path is appended only in dev mode — it is intentionally
    # absent from the published keystone-deepwork-jobs package.
    home.sessionVariables = {
      DEEPWORK_ADDITIONAL_JOBS_FOLDERS = builtins.concatStringsSep ":" (
        [
          (
            if isDev && !isAgent && deepworkPath != null then
              "${deepworkPath}/library/jobs"
            else
              "${pkgs.keystone.deepwork-library-jobs}"
          )
          (
            if isDev && !isAgent && keystonePath != null then
              "${keystonePath}/.deepwork/jobs"
            else
              "${pkgs.keystone.keystone-deepwork-jobs}"
          )
        ]
        ++ lib.optional (
          isDev && !isAgent && keystonePath != null
        ) "${keystonePath}/.deepwork/jobs-internal"
      );
    };
  };
}
