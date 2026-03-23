# Keystone Repos & Development Mode
#
# Implements REQ-018.3: managed repo registry with auto-population from flake inputs.
#
# keystone.repos declares managed repositories keyed by owner/repo.
# keystone.development enables local checkout path resolution across all modules.
#
# Repos are auto-populated from flake inputs passed via keystone._repoInputs.
# Only inputs with discoverable source URLs (github, git) are registered.
# Auto-derived entries use mkDefault priority so consumers can override.
#
{ lib, config, ... }:
with lib;
let
  cfg = config.keystone;
  inputs = cfg._repoInputs;

  # Derive a repo entry from a flake input's sourceInfo.
  # Returns null for inputs without a discoverable git URL.
  # Handles github (owner/repo) and git (direct URL) input types.
  mkRepoEntry =
    name: input:
    let
      si = input.sourceInfo or { };
      type = si.type or "";
    in
    if type == "github" && si ? owner && si ? repo then
      {
        name = "${si.owner}/${si.repo}";
        value = {
          url = "https://github.com/${si.owner}/${si.repo}.git";
          flakeInput = name;
          branch = "main";
        };
      }
    else if type == "git" && si ? url then
      {
        inherit name;
        value = {
          url = si.url;
          flakeInput = name;
          branch = "main";
        };
      }
    else
      null;

  autoEntries = filter (e: e != null) (mapAttrsToList mkRepoEntry inputs);
  autoRepos = listToAttrs autoEntries;
in
{
  options.keystone = {
    development = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable development mode globally. When true, modules use local repo
        checkouts at ~/.keystone/repos/OWNER/REPO/ instead of Nix store copies.
        Requires keystone.repos to declare managed repositories.

        This defaults to false per process.enable-by-default exception rule 17 —
        development mode requires local repo checkouts to function.
      '';
    };

    _repoInputs = mkOption {
      type = types.attrs;
      default = { };
      internal = true;
      description = "Flake inputs for auto-deriving keystone.repos entries. Only inputs with discoverable source URLs are registered.";
    };

    repos = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            url = mkOption {
              type = types.str;
              description = "Git remote URL";
            };
            flakeInput = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Corresponding flake input name for --override-input in dev mode.";
            };
            branch = mkOption {
              type = types.str;
              default = "main";
              description = "Default branch for pull/push";
            };
          };
        }
      );
      default = { };
      description = "Managed repositories keyed by owner/repo. Cloned to ~/.keystone/repos/{owner}/{repo}/.";
    };
  };

  config.keystone.repos = mkIf (inputs != { }) (mapAttrs (_: v: mkDefault v) autoRepos);
}
