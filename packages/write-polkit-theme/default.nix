{
  writeShellApplication,
  jq,
}:
# Single source of truth for the keystone polkit-theme JSON generator.
# Both production (modules/desktop/home/theming/default.nix — the home.activation
# script and the keystone-theme-switch wrapper) and the dev smoke test
# (bin/dev/test-polkit-theme.sh) call this binary, so the smoke test exercises
# the same logic that ships.
writeShellApplication {
  name = "keystone-write-polkit-theme";
  runtimeInputs = [ jq ];
  text = ''
    if [[ $# -ne 2 ]]; then
      echo "Usage: keystone-write-polkit-theme <theme-path> <output-path>" >&2
      exit 2
    fi

    theme_path="$1"
    output_path="$2"
    hyprlock_file="$theme_path/hyprlock.conf"
    waybar_file="$theme_path/waybar.css"
    is_light=false

    read_hyprlock_color() {
      local name="$1"
      if [[ -f "$hyprlock_file" ]]; then
        sed -n 's/^\$'"$name"' = \(rgb([^)]*)\).*/\1/p' "$hyprlock_file" | head -1
      fi
    }

    read_waybar_color() {
      local name="$1"
      if [[ -f "$waybar_file" ]]; then
        sed -n 's/^@define-color '"$name"' \([^;]*\);/\1/p' "$waybar_file" | head -1
      fi
    }

    if [[ -f "$theme_path/light.mode" ]]; then
      is_light=true
    fi

    # Prefer waybar's @define-color background over hyprlock's $color.
    # Hyprlock is tuned for a full-screen lock and is the darkest variant of
    # a theme (royal-green hyprlock = rgb(0,18,12) ≈ near-black; waybar =
    # #001F14, visibly green). The polkit dialog is a panel-ish surface, so
    # waybar's brightness is a closer fit.
    background="$(read_waybar_color background)"
    [[ -n "$background" ]] || background="$(read_hyprlock_color color)"
    [[ -n "$background" ]] || background="#111827"

    surface="$background"

    border="$(read_hyprlock_color outer_color)"
    [[ -n "$border" ]] || border="$(read_waybar_color gold)"
    [[ -n "$border" ]] || border="#334155"

    accent="$border"

    # Hyprlock's $font_color is the password-prompt text colour — the polkit
    # dialog is semantically the same kind of surface (small auth modal), so
    # its text colour should match. Waybar's @foreground is tuned for panel
    # text, which on themes like royal-green is silvery while the lock prompt
    # is gold — preferring waybar there makes the polkit dialog read off-theme.
    text="$(read_hyprlock_color font_color)"
    [[ -n "$text" ]] || text="$(read_waybar_color foreground)"
    [[ -n "$text" ]] || text="#e5e7eb"

    placeholder="$(read_hyprlock_color placeholder_color)"
    [[ -n "$placeholder" ]] || placeholder="$text"

    muted_text="$placeholder"

    if [[ "$is_light" == true ]]; then
      error="#b42318"
    else
      error="#fb7185"
    fi

    mkdir -p "$(dirname "$output_path")"
    jq -n \
      --arg background "$background" \
      --arg surface "$surface" \
      --arg border "$border" \
      --arg accent "$accent" \
      --arg text "$text" \
      --arg mutedText "$muted_text" \
      --arg placeholder "$placeholder" \
      --arg error "$error" \
      --argjson light "$is_light" \
      '{
        background: $background,
        surface: $surface,
        border: $border,
        accent: $accent,
        text: $text,
        mutedText: $mutedText,
        placeholder: $placeholder,
        error: $error,
        light: $light
      }' > "$output_path"
  '';
}
