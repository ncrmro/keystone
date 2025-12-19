{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

  # Custom satty package using the latest source from GitHub
  # The default version of satty is 0.18.1 and uses --action-on-enter (singular)
  # Version 0.19.0+ uses --actions-on-enter (plural) which our script requires
  satty-latest = pkgs.satty.overrideAttrs (oldAttrs: rec {
    version = "0.20.0";
    src = pkgs.fetchFromGitHub {
      owner = "gabm";
      repo = "Satty";
      rev = "v0.20.0";
      hash = "sha256-4RVah6yo4cJyE6qUbDJbcmFpi7xsKNpHJFrzSs1yJcg=";
    };
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "${oldAttrs.pname}-${version}";
      hash = "sha256-RPj6ZVtDWPMt4jrmU750b7zLVHwqk+SWr2OskDAQFYI=";
    };
  });

  # Screenshot script - supports region, windows, fullscreen, and smart modes
  keystoneScreenshot = pkgs.writeShellScriptBin "keystone-screenshot" ''
    [[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
    OUTPUT_DIR="''${KEYSTONE_SCREENSHOT_DIR:-''${XDG_PICTURES_DIR:-$HOME/Pictures}}"

    if [[ ! -d "$OUTPUT_DIR" ]]; then
      ${pkgs.libnotify}/bin/notify-send "Screenshot directory does not exist: $OUTPUT_DIR" -u critical -t 3000
      exit 1
    fi

    ${pkgs.procps}/bin/pkill slurp && exit 0

    MODE="''${1:-smart}"
    PROCESSING="''${2:-slurp}"

    get_rectangles() {
      local active_workspace=$(${hyprlandPkg}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true) | .activeWorkspace.id')
      ${hyprlandPkg}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r --arg ws "$active_workspace" '.[] | select(.activeWorkspace.id == ($ws | tonumber)) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"'
      ${hyprlandPkg}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -r --arg ws "$active_workspace" '.[] | select(.workspace.id == ($ws | tonumber)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
    }

    case "$MODE" in
      region)
        ${pkgs.wayfreeze}/bin/wayfreeze & PID=$!
        sleep .1
        SELECTION=$(${pkgs.slurp}/bin/slurp 2>/dev/null)
        kill $PID 2>/dev/null
        ;;
      windows)
        ${pkgs.wayfreeze}/bin/wayfreeze & PID=$!
        sleep .1
        SELECTION=$(get_rectangles | ${pkgs.slurp}/bin/slurp -r 2>/dev/null)
        kill $PID 2>/dev/null
        ;;
      fullscreen)
        SELECTION=$(${hyprlandPkg}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"')
        ;;
      smart|*)
        RECTS=$(get_rectangles)
        ${pkgs.wayfreeze}/bin/wayfreeze & PID=$!
        sleep .1
        SELECTION=$(echo "$RECTS" | ${pkgs.slurp}/bin/slurp 2>/dev/null)
        kill $PID 2>/dev/null

        if [[ "$SELECTION" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
          if (( ''${BASH_REMATCH[3]} * ''${BASH_REMATCH[4]} < 20 )); then
            click_x="''${BASH_REMATCH[1]}"
            click_y="''${BASH_REMATCH[2]}"

            while IFS= read -r rect; do
              if [[ "$rect" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+) ]]; then
                rect_x="''${BASH_REMATCH[1]}"
                rect_y="''${BASH_REMATCH[2]}"
                rect_width="''${BASH_REMATCH[3]}"
                rect_height="''${BASH_REMATCH[4]}"

                if (( click_x >= rect_x && click_x < rect_x+rect_width && click_y >= rect_y && click_y < rect_y+rect_height )); then
                  SELECTION="''${rect_x},''${rect_y} ''${rect_width}x''${rect_height}"
                  break
                fi
              fi
            done <<< "$RECTS"
          fi
        fi
        ;;
    esac

    [ -z "$SELECTION" ] && exit 0

    if [[ $PROCESSING == "slurp" ]]; then
      ${pkgs.grim}/bin/grim -g "$SELECTION" - |
        ${satty-latest}/bin/satty --filename - \
          --output-filename "$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png" \
          --early-exit \
          --actions-on-enter save-to-clipboard \
          --save-after-copy \
          --copy-command '${pkgs.wl-clipboard}/bin/wl-copy'
    else
      ${pkgs.grim}/bin/grim -g "$SELECTION" - | ${pkgs.wl-clipboard}/bin/wl-copy
    fi
  '';
in
{
  config = mkIf cfg.enable {
    home.packages = [
      keystoneScreenshot
      pkgs.grim
      pkgs.slurp
      satty-latest
      pkgs.wayfreeze
      pkgs.hyprpicker
      pkgs.jq
    ];

    # Satty configuration - Ctrl+C copies to clipboard, saves file, and exits
    xdg.configFile."satty/config.toml".text = ''
      [general]
      early-exit = true
      save-after-copy = true
      copy-command = "${pkgs.wl-clipboard}/bin/wl-copy"
    '';

    # Hyprland layer rule to remove animation artifacts during screenshot selection
    wayland.windowManager.hyprland.settings.layerrule = [ "no_anim on, match:namespace slurp" ];
  };
}
