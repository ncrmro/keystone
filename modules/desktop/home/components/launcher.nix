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
  localBin = "${config.home.homeDirectory}/.local/bin";
  projectsDesktopEntry = ''
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=Projects
    GenericName=Project context switcher
    Comment=Open the Keystone project selector
    Exec=${localBin}/keystone-context-switch
    Terminal=false
    Categories=Utility;Development;
    Icon=folder-development
  '';
  notesDesktopEntry = ''
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=Notes
    GenericName=Inbox note capture
    Comment=Open zk inbox capture in a floating window
    Exec=${localBin}/keystone-notes-inbox
    Terminal=false
    Categories=Utility;Office;
    Icon=notes
  '';

  # Read and substitute the walker style.css template
  walkerStyleCss = builtins.replaceStrings [ "\${themeDir}" ] [ themeDir ] (
    builtins.readFile ./walker-style.css
  );

  # Read the layout XML
  walkerLayoutXml = builtins.readFile ./walker-layout.xml;

  # Substitute tool paths in the walker lua scripts
  substituteLua =
    text:
    builtins.replaceStrings
      [
        "pz export-menu-data"
        "pz sessions"
        "keystone-project-menu"
      ]
      [
        "${localBin}/pz export-menu-data"
        "${localBin}/pz sessions"
        "${localBin}/keystone-project-menu"
      ]
      text;

  keystoneProjectsMenuLua = substituteLua (builtins.readFile ./keystone-projects.lua);
  keystoneProjectDetailsMenuLua = substituteLua (builtins.readFile ./keystone-project-details.lua);
  keystoneProjectSessionMenuLua = substituteLua (builtins.readFile ./keystone-project-session.lua);
in
{
  # walker is imported via flake.nix homeModules.desktop (hoisted to avoid
  # _module.args infinite recursion when keystoneInputs is used in imports)

  config = mkIf cfg.enable {
    home.file.".local/share/applications/keystone-projects.desktop" = {
      text = projectsDesktopEntry;
      executable = false;
    };

    home.file.".local/share/applications/keystone-notes.desktop" = {
      text = notesDesktopEntry;
      executable = false;
    };

    home.file.".config/elephant/menus/keystone-projects.lua".text = keystoneProjectsMenuLua;
    home.file.".config/elephant/menus/keystone-project-details.lua".text =
      keystoneProjectDetailsMenuLua;
    home.file.".config/elephant/menus/keystone-project-session.lua".text =
      keystoneProjectSessionMenuLua;

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
        actions_as_menu = true;
        hide_action_hints = false;

        placeholders = {
          default = {
            input = " Search...";
            list = "No Results";
          };
          "menus:keystone-projects" = {
            input = " Projects";
            list = "No projects found";
          };
          "menus:keystone-project-details" = {
            input = " Project actions";
            list = "No project actions";
          };
          "menus:keystone-project-session" = {
            input = " Session slug";
            list = "Press Enter to create the session";
          };
        };

        keybinds = {
          next = [ "Down" ];
          previous = [ "Up" ];
          quick_activate = [ ];
          show_actions = [ ];
        };

        providers = {
          max_results = 256;
          default = [
            "desktopapplications"
            "websearch"
          ];
          sets.keystone-projects = {
            default = [ "menus:keystone-projects" ];
            empty = [ "menus:keystone-projects" ];
          };
          actions = {
            fallback = [
              {
                action = "menus:open";
                label = "open";
                after = "Nothing";
                default = true;
              }
              {
                action = "erase_history";
                label = "clear hist";
                bind = "ctrl h";
                after = "AsyncReload";
              }
            ];
          };
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
