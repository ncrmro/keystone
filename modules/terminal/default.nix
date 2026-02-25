{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
in {
  imports = [
    ./shell.nix
    ./editor.nix
    ./ai.nix
    ./age-yubikey.nix
    ./devtools.nix
    ./mail.nix
  ];

  options.keystone.terminal = {
    enable = mkEnableOption "Keystone Terminal - Core terminal tools and configuration";

    devTools = mkOption {
      type = types.bool;
      default = false;
      description = "Enable additional development tools (csview, jq)";
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

    # Configure git when enabled
    programs.git = mkIf cfg.git.enable {
      enable = true;
      lfs.enable = mkDefault true;

      settings = mkDefault {
        user = {
          name = cfg.git.userName;
          email = cfg.git.userEmail;
        };
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
      };
    };

    programs.lazygit.enable = mkIf cfg.git.enable (mkDefault true);
  };
}
