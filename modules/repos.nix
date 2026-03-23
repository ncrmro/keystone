# Keystone Repos & Development Mode
#
# Implements REQ-018.3 (repo registry) and process.keystone-development-mode convention.
#
# keystone.repos declares managed repositories keyed by owner/repo.
# keystone.development enables local checkout path resolution across all modules.
#
{ lib, ... }:
with lib;
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

    repos = mkOption {
      type = types.attrsOf (types.submodule {
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
      });
      default = { };
      description = "Managed repositories keyed by owner/repo. Cloned to ~/.keystone/repos/{owner}/{repo}/.";
    };
  };
}
