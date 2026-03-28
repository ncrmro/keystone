{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  devScripts = import ../../../shared/dev-script-link.nix { inherit lib; };
  inherit (devScripts) mkHomeRepoFiles;
  themeDir = "${config.xdg.configHome}/keystone/current/theme";

  # Read and substitute the walker style.css template
  walkerStyleCss = builtins.replaceStrings [ "\${themeDir}" ] [ themeDir ] (
    builtins.readFile ./walker-style.css
  );

  # TODO(REQ-018.7a): Home Manager's Walker module currently embeds layout XML
  # inline, so this remains generated until Walker layouts can be referenced by
  # path without losing dev-mode behavior.
  walkerLayoutXml = builtins.readFile ./walker-layout.xml;
in
{
  # walker is imported via flake.nix homeModules.desktop (hoisted to avoid
  # _module.args infinite recursion when keystoneInputs is used in imports)

  config = mkIf cfg.enable (mkMerge [
    (mkHomeRepoFiles {
      inherit config;
      files = [
        {
          targetPath = ".local/share/applications/keystone-projects.desktop";
          relativePath = "modules/desktop/home/components/keystone-projects.desktop";
          sourcePath = ./keystone-projects.desktop;
        }
        {
          targetPath = ".local/share/applications/keystone-notes.desktop";
          relativePath = "modules/desktop/home/components/keystone-notes.desktop";
          sourcePath = ./keystone-notes.desktop;
        }
        {
          targetPath = ".config/elephant/menus/keystone-projects.lua";
          relativePath = "modules/desktop/home/components/keystone-projects.lua";
          sourcePath = ./keystone-projects.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-project-details.lua";
          relativePath = "modules/desktop/home/components/keystone-project-details.lua";
          sourcePath = ./keystone-project-details.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-project-notes.lua";
          relativePath = "modules/desktop/home/components/keystone-project-notes.lua";
          sourcePath = ./keystone-project-notes.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-project-session.lua";
          relativePath = "modules/desktop/home/components/keystone-project-session.lua";
          sourcePath = ./keystone-project-session.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-monitors.lua";
          relativePath = "modules/desktop/home/components/keystone-monitors.lua";
          sourcePath = ./keystone-monitors.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-monitor-actions.lua";
          relativePath = "modules/desktop/home/components/keystone-monitor-actions.lua";
          sourcePath = ./keystone-monitor-actions.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-monitor-values.lua";
          relativePath = "modules/desktop/home/components/keystone-monitor-values.lua";
          sourcePath = ./keystone-monitor-values.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-audio.lua";
          relativePath = "modules/desktop/home/components/keystone-audio.lua";
          sourcePath = ./keystone-audio.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-audio-devices.lua";
          relativePath = "modules/desktop/home/components/keystone-audio-devices.lua";
          sourcePath = ./keystone-audio-devices.lua;
        }
      ];
    })
    {
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
          resume_last_query = false;
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
            "menus:keystone-project-notes" = {
              input = " Project notes";
              list = "No project notes";
            };
            "menus:keystone-project-session" = {
              input = " Session slug";
              list = "Press Enter to create the session";
            };
            "menus:keystone-monitors" = {
              input = " Monitors";
              list = "No monitors found";
            };
            "menus:keystone-monitor-actions" = {
              input = " Monitor actions";
              list = "No actions available";
            };
            "menus:keystone-monitor-values" = {
              input = " Monitor values";
              list = "No values available";
            };
            "menus:keystone-audio" = {
              input = " Audio";
              list = "No audio actions available";
            };
            "menus:keystone-audio-devices" = {
              input = " Audio devices";
              list = "No audio devices found";
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
    }
  ]);
}
