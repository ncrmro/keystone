# Keystone Terminal — core terminal module entry point.
# Implements REQ-002 (Terminal Development Environment)
# See specs/REQ-018-repo-management/ (development mode)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;

  # Generate allowed_signers file content: "<email> <key>" per line
  allowedSignersContent = concatMapStringsSep "\n" (
    key: "${cfg.git.userEmail} ${key}"
  ) cfg.git.sshPublicKeys;
in
{
  imports = [
    ./shell.nix
    ./editor.nix
    ./ai.nix
    ./deepwork.nix
    ./age-yubikey.nix
    ./devtools.nix
    ./mail.nix
    ./calendar.nix
    ./contacts.nix
    ./timer.nix
    ./tasks.nix
    ./agent-mail.nix
    ./sandbox.nix
    ./secrets.nix
    ./ssh-auto-load.nix
    ./forgejo.nix
    ./projects.nix
    ./cli-coding-agent-configs.nix
    ./conventions.nix
    ./ai-extensions.nix
    ./perception.nix
  ];

  options.keystone.terminal = {
    enable = mkEnableOption "Keystone Terminal - Core terminal tools and configuration";

    devTools = mkOption {
      type = types.bool;
      default = false;
      description = "Enable additional development tools (csview)";
    };

    editor = mkOption {
      type = types.str;
      default = "hx";
      description = "Default editor command (e.g., 'hx' for helix, 'nvim' for neovim)";
    };

    development = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable development mode. When true, terminal modules use local repo
        checkouts at ~/.keystone/repos/OWNER/REPO/ instead of Nix store copies,
        enabling rapid iteration without rebuilding.

        Bridged from the NixOS-level keystone.development option by users.nix.
      '';
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
              description = "Corresponding flake input name.";
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
      description = ''
        Managed repositories keyed by owner/repo. Used in development mode to
        resolve local checkout paths. Bridged from keystone.repos by users.nix.
      '';
    };

    git = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable git configuration with keystone defaults";
      };

      userName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Full name for git commits (required when git.enable is true)";
        example = "John Doe";
      };

      userEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Email address for git commits (required when git.enable is true)";
        example = "john@example.com";
      };

      sshPublicKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "SSH public keys for allowed_signers (git signature verification).";
      };

      signingKey = mkOption {
        type = types.str;
        default = "~/.ssh/id_ed25519";
        description = "SSH key for signing. Path or 'key::' prefix for inline public key.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Assertions to ensure required git options are set
    assertions = [
      {
        assertion = !cfg.git.enable || cfg.git.userName != null;
        message = "keystone.terminal.git.userName must be set when keystone.terminal.git.enable is true";
      }
      {
        assertion = !cfg.git.enable || cfg.git.userEmail != null;
        message = "keystone.terminal.git.userEmail must be set when keystone.terminal.git.enable is true";
      }
    ];

    # Generate allowed_signers file when SSH public keys are provided
    home.file.".ssh/allowed_signers" = mkIf (cfg.git.enable && cfg.git.sshPublicKeys != [ ]) {
      text = allowedSignersContent;
    };

    # Configure git when enabled
    programs.git = mkIf cfg.git.enable {
      enable = true;
      lfs.enable = mkDefault true;

      settings = mkDefault {
        user = {
          name = cfg.git.userName;
          email = cfg.git.userEmail;
          signingkey = cfg.git.signingKey;
        };
        gpg.format = "ssh";
        gpg.ssh.allowedSignersFile = mkIf (cfg.git.sshPublicKeys != [ ]) "~/.ssh/allowed_signers";
        commit.gpgsign = true;
        tag.gpgsign = true;
        alias = {
          s = "switch";
          f = "fetch";
          p = "pull";
          b = "branch";
          st = "status -sb";
          co = "checkout";
          c = "commit";
        };
        push.autoSetupRemote = true;
        init.defaultBranch = "main";
        submodule.recurse = true;
      };
    };

    home.packages = optionals cfg.git.enable [
      pkgs.keystone.fetch-github-sources
    ];

    programs.lazygit.enable = mkIf cfg.git.enable (mkDefault true);
  };
}
