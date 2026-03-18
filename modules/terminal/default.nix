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
  allowedSignersContent = concatMapStringsSep "\n" (key:
    "${cfg.git.userEmail} ${key}"
  ) cfg.git.sshPublicKeys;
in {
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
    ./agent-mail.nix
    ./sandbox.nix
    ./secrets.nix
    ./ssh-auto-load.nix
    ./forgejo.nix
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
        default = [];
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
    home.file.".ssh/allowed_signers" = mkIf (cfg.git.enable && cfg.git.sshPublicKeys != []) {
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
        gpg.ssh.allowedSignersFile = mkIf (cfg.git.sshPublicKeys != []) "~/.ssh/allowed_signers";
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

    home.packages = mkIf cfg.git.enable [
      pkgs.keystone.fetch-github-sources
    ];

    programs.lazygit.enable = mkIf cfg.git.enable (mkDefault true);
  };
}
