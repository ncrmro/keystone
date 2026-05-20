# Keystone Terminal — GitHub PATs
#
# Provides a two-PAT model for GitHub authentication:
#   - User PAT: broad-scope interactive token. Exported as GITHUB_TOKEN /
#     GH_TOKEN at shell startup so `gh`, `git`, and any tool that reads these
#     env vars work without manual `gh auth login`. Also consumed by the
#     `ghcr-login` helper for ghcr.io registry login.
#   - Agents PAT: narrower-scope token used by autonomous agent flows. The
#     token value is NEVER exported as GITHUB_TOKEN — only the file path is
#     exported as GITHUB_AGENTS_TOKEN_FILE so agent harnesses load it
#     explicitly.
#
# Adopter contract:
#   - Declare age.secrets entries for each token on every host where the
#     home-manager user runs.
#   - Set userTokenFile / agentsTokenFile to the decrypted runtime paths.
#   - See conventions/tool.github-pats.md for scopes, naming, and recipients.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
  ghCfg = cfg.github;

  userTokenInit = ''
    if [ -r "${ghCfg.userTokenFile}" ]; then
      GITHUB_TOKEN="$(tr -d '\n' < "${ghCfg.userTokenFile}")"
      export GITHUB_TOKEN
      export GH_TOKEN="$GITHUB_TOKEN"
    fi
  '';

  ghcrLoginFn = ''
    ghcr-login() {
      local file="${ghCfg.userTokenFile}"
      if [ ! -r "$file" ]; then
        echo "ghcr-login: token file not readable: $file" >&2
        return 1
      fi
      local cli
      if command -v podman >/dev/null 2>&1; then
        cli=podman
      elif command -v docker >/dev/null 2>&1; then
        cli=docker
      else
        echo "ghcr-login: neither podman nor docker found on PATH" >&2
        return 1
      fi
      tr -d '\n' < "$file" | "$cli" login ghcr.io -u "${toString ghCfg.username}" --password-stdin
    }
  '';

  shellInit = userTokenInit + optionalString ghCfg.ghcrLoginHelper ghcrLoginFn;
in
{
  options.keystone.terminal.github = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable keystone GitHub PAT wiring (env vars + ghcr-login helper).";
    };

    username = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ncrmro";
      description = "GitHub username. Required when enable is true (used by ghcr-login).";
    };

    userTokenFile = mkOption {
      type = types.str;
      default = if ghCfg.username == null then "" else "/run/agenix/${ghCfg.username}-github-token";
      defaultText = literalExpression ''"/run/agenix/''${cfg.github.username}-github-token"'';
      description = ''
        Path to the decrypted user PAT (broad scope). The keystone module reads
        this file at shell startup and exports GITHUB_TOKEN/GH_TOKEN. The
        adopter is responsible for declaring an age.secrets entry that
        produces this file with owner=<user> mode=0400.
      '';
    };

    agentsTokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/agenix/github-agents-token";
      description = ''
        Path to the decrypted agents PAT (narrow scope). When set,
        GITHUB_AGENTS_TOKEN_FILE is exported pointing at this path. The token
        value is never exported as GITHUB_TOKEN — agents must read the file
        explicitly so the broader user PAT remains the only ambient
        credential.
      '';
    };

    ghcrLoginHelper = mkOption {
      type = types.bool;
      default = true;
      description = "Install the `ghcr-login` shell function (uses podman, falls back to docker).";
    };
  };

  config = mkIf (cfg.enable && ghCfg.enable) {
    assertions = [
      {
        assertion = ghCfg.username != null;
        message = "keystone.terminal.github.username must be set when keystone.terminal.github.enable is true";
      }
      {
        assertion = ghCfg.userTokenFile != "";
        message = "keystone.terminal.github.userTokenFile must be set (or set username so the default resolves)";
      }
    ];

    programs.zsh.initExtra = shellInit;
    programs.bash.initExtra = shellInit;

    home.sessionVariables = optionalAttrs (ghCfg.agentsTokenFile != null) {
      GITHUB_AGENTS_TOKEN_FILE = ghCfg.agentsTokenFile;
    };
  };
}
