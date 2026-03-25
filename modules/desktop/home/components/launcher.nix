{
  config,
  lib,
  pkgs,
  keystoneInputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  themeDir = "${config.xdg.configHome}/keystone/current/theme";

  # Read and substitute the walker style.css template
  walkerStyleCss = builtins.replaceStrings [ "\${themeDir}" ] [ themeDir ] (
    builtins.readFile ./walker-style.css
  );

  # Read the layout XML
  walkerLayoutXml = builtins.readFile ./walker-layout.xml;
in
{
  # walker is imported via flake.nix homeModules.desktop (hoisted to avoid
  # _module.args infinite recursion when keystoneInputs is used in imports)

  config = mkIf cfg.enable {
    xdg.desktopEntries.keystone-projects = {
      name = "Projects";
      genericName = "Project context switcher";
      comment = "Open the Keystone project selector";
      exec = "keystone-context-switch";
      terminal = false;
      categories = [
        "Utility"
        "Development"
      ];
      icon = "folder-development";
    };

    # Wofi as the application launcher
    programs.wofi = {
      enable = mkDefault true;
      settings = {
        show = "drun";
        width = 600;
        height = 400;
        term = "ghostty";
        prompt = "Search...";
        allow_images = true;
        image_size = 24;
        insensitive = true;
      };
      style = ''
        @import "${config.xdg.configHome}/keystone/current/theme/wofi.css";
      '';
    };

    # Walker launcher using the official home-manager module
    programs.walker = {
      enable = mkDefault true;
      runAsService = true;

      config = {
        force_keyboard_focus = true;
        selection_wrap = true;
        theme = "keystone";
        hide_action_hints = true;

        placeholders = {
          default = {
            input = " Search...";
            list = "No Results";
          };
        };

        keybinds = {
          quick_activate = [ ];
        };

        providers = {
          max_results = 256;
          default = [
            "desktopapplications"
            "websearch"
          ];
          prefixes = [
            {
              prefix = "/";
              provider = "providerlist";
            }
            {
              prefix = ".";
              provider = "files";
            }
            {
              prefix = ":";
              provider = "symbols";
            }
            {
              prefix = "=";
              provider = "calc";
            }
            {
              prefix = "@";
              provider = "websearch";
            }
            {
              prefix = "$";
              provider = "clipboard";
            }
          ];
        };
      };

      # Define the keystone theme
      themes.keystone = {
        style = walkerStyleCss;
        layouts = {
          layout = walkerLayoutXml;
        };
      };
    };
  };
}
