#!/usr/bin/env bash
# Smoke-test the keystone hyprpolkitagent dialog against one or more
# keystone themes. Validates that:
#   1. write_polkit_theme() emits valid JSON for the theme
#   2. hyprpolkitagent restarts cleanly (no QML parse errors,
#      no QQuickStyle fallback chain, no XHR file-read denial)
#   3. The dialog renders and pkexec round-trips a no-op activation
#   4. (Interactive only) the user confirms the dialog looks right
#
# Run between major keystone updates that touch the polkit agent,
# the polkit theme generator, or the active theme set.
#
# Usage:
#   bin/dev/test-polkit-theme.sh                 # current theme, interactive
#   bin/dev/test-polkit-theme.sh --theme NAME    # specific theme
#   bin/dev/test-polkit-theme.sh --all           # iterate every theme
#   bin/dev/test-polkit-theme.sh --headless      # no visual confirmation
#   bin/dev/test-polkit-theme.sh --reset         # restore live polkit.json
#
# Notes:
#   - Edits ~/.config/keystone/current/polkit.json in place. The original
#     is snapshotted to ${LIVE_THEME}.test-snapshot and restored on EXIT,
#     INT, TERM. Run --reset if a previous run was killed mid-test.
#   - Uses pkexec directly (not `ks approve`) so a missing graphical
#     session doesn't fall back to a tty password prompt.
#   - The pkexec target is `ks activate /run/current-system`, which the
#     allowlist accepts and which is a no-op against the running system.

set -u
set -o pipefail

LIVE_THEME=${KEYSTONE_POLKIT_THEME:-$HOME/.config/keystone/current/polkit.json}
THEMES_DIR=${KEYSTONE_THEMES_DIR:-$HOME/.config/keystone/themes}
CURRENT_LINK=${KEYSTONE_CURRENT_LINK:-$HOME/.config/keystone/current/theme}
SNAPSHOT="${LIVE_THEME}.test-snapshot"
LOG_DIR=${KEYSTONE_POLKIT_TEST_LOG_DIR:-$HOME/.cache/keystone-polkit-tests}
LOG_FILE="$LOG_DIR/log"
HELPER=${KEYSTONE_APPROVE_EXEC:-/run/current-system/sw/bin/keystone-approve-exec}
PKEXEC=${PKEXEC_BIN:-/run/wrappers/bin/pkexec}
AGENT_UNIT=hyprpolkitagent.service

THEME_ARG=""
RUN_ALL=0
HEADLESS=0
RESET=0

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme)    THEME_ARG="${2:-}"; shift 2 ;;
    --theme=*)  THEME_ARG="${1#--theme=}"; shift ;;
    --all)      RUN_ALL=1; shift ;;
    --headless) HEADLESS=1; shift ;;
    --reset)    RESET=1; shift ;;
    -h|--help)  usage 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage 1
      ;;
  esac
done

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$LOG_FILE"
}

restore_snapshot() {
  if [[ -f "$SNAPSHOT" ]]; then
    mv "$SNAPSHOT" "$LIVE_THEME"
    systemctl --user restart "$AGENT_UNIT" 2>/dev/null || true
    log "snapshot restored to $LIVE_THEME"
  fi
}

# Reset mode: just restore and exit. Useful if a previous run died
# without unwinding (ctrl-c during the visual prompt, killed terminal,
# etc).
if [[ "$RESET" -eq 1 ]]; then
  if [[ -f "$SNAPSHOT" ]]; then
    restore_snapshot
    echo "polkit.json restored from snapshot"
  else
    echo "no snapshot at $SNAPSHOT; nothing to restore"
  fi
  exit 0
fi

trap restore_snapshot EXIT INT TERM

# Port of write_polkit_theme() from modules/desktop/home/theming/default.nix.
# We deliberately re-implement here rather than shelling out to the
# generated keystone-theme-switch wrapper because that wrapper also
# restarts waybar/mako/walker — too noisy for a test loop. The function
# below MUST stay in sync with the Nix definition; the docs note this.
write_polkit_theme() {
  local theme_path="$1"
  local output_path="$2"
  local hyprlock_file="$theme_path/hyprlock.conf"
  local waybar_file="$theme_path/waybar.css"
  local is_light=false
  local background=""
  local surface=""
  local border=""
  local accent=""
  local text=""
  local muted_text=""
  local placeholder=""
  local error=""

  read_hyprlock_color() {
    local name="$1"
    if [[ -f "$hyprlock_file" ]]; then
      sed -n "s/^\$${name} = \(rgb([^)]*)\).*/\1/p" "$hyprlock_file" | head -1
    fi
  }

  read_waybar_color() {
    local name="$1"
    if [[ -f "$waybar_file" ]]; then
      sed -n "s/^@define-color $name \([^;]*\);/\1/p" "$waybar_file" | head -1
    fi
  }

  if [[ -f "$theme_path/light.mode" ]]; then
    is_light=true
  fi

  background="$(read_hyprlock_color color)"
  [[ -n "$background" ]] || background="$(read_waybar_color background)"
  [[ -n "$background" ]] || background="#111827"

  surface="$(read_hyprlock_color inner_color)"
  [[ -n "$surface" ]] || surface="$background"

  border="$(read_hyprlock_color outer_color)"
  [[ -n "$border" ]] || border="$(read_waybar_color gold)"
  [[ -n "$border" ]] || border="#334155"

  accent="$border"

  text="$(read_waybar_color foreground)"
  [[ -n "$text" ]] || text="$(read_hyprlock_color font_color)"
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
}

resolve_theme_dir() {
  local name="$1"
  if [[ -d "$THEMES_DIR/$name" ]]; then
    printf '%s\n' "$THEMES_DIR/$name"
    return 0
  fi
  return 1
}

current_theme_name() {
  if [[ -L "$CURRENT_LINK" ]]; then
    basename "$(readlink -f "$CURRENT_LINK")"
  else
    echo ""
  fi
}

run_one() {
  local theme_name="$1"
  local theme_dir
  theme_dir="$(resolve_theme_dir "$theme_name")" || {
    log "FAIL [$theme_name]: theme directory not found under $THEMES_DIR"
    return 1
  }

  log "==> testing theme: $theme_name (path: $theme_dir)"

  # Step 1: regenerate polkit.json from theme.
  if ! write_polkit_theme "$theme_dir" "$LIVE_THEME"; then
    log "FAIL [$theme_name]: write_polkit_theme failed"
    return 1
  fi
  log "  generated $LIVE_THEME"

  # Step 2: validate JSON shape.
  local missing
  missing=$(jq -r '
    ["background","surface","border","accent","text","mutedText","placeholder","error","light"]
    - (keys)
    | .[]
  ' "$LIVE_THEME" 2>/dev/null) || {
    log "FAIL [$theme_name]: polkit.json is not valid JSON"
    return 1
  }
  if [[ -n "$missing" ]]; then
    log "FAIL [$theme_name]: polkit.json missing keys: $(tr '\n' ' ' <<<"$missing")"
    return 1
  fi
  log "  json validated (all keys present)"

  # Echo the colors so a reviewer can sanity-check them against the
  # theme files without opening jq separately.
  jq -r '"  bg=\(.background) surface=\(.surface) border=\(.border) text=\(.text)"' "$LIVE_THEME" \
    | tee -a "$LOG_FILE"

  # Step 3: restart agent and capture stderr from the journal.
  # reset-failed first so that rapid iteration in --all doesn't trip
  # systemd's StartLimitBurst (default 5 restarts / 10s).
  local start_ts
  start_ts=$(date '+%Y-%m-%d %H:%M:%S')
  systemctl --user reset-failed "$AGENT_UNIT" 2>/dev/null || true
  if ! systemctl --user restart "$AGENT_UNIT"; then
    log "FAIL [$theme_name]: failed to restart $AGENT_UNIT"
    return 1
  fi
  # Brief settle before pkexec talks to the agent on the user bus.
  sleep 1

  # Step 4: scan the agent journal for known-bad signals. We tolerate
  # the kvantum platformtheme line because it's a noisy-but-harmless
  # init message in the upstream Qt build.
  local agent_errors
  agent_errors=$(journalctl --user -u "$AGENT_UNIT" --since "$start_ts" --no-pager 2>&1 \
    | grep -E 'QQuickStyle|file:.*XMLHttpRequest|qrc:/main\.qml.*Error|Cannot read property|QML.*ReferenceError' \
    || true)
  if [[ -n "$agent_errors" ]]; then
    log "FAIL [$theme_name]: agent reported QML/style errors:"
    printf '%s\n' "$agent_errors" | sed 's/^/    /' | tee -a "$LOG_FILE"
    return 1
  fi
  log "  agent restart clean (no QML/style errors in journal)"

  # Step 5: trigger an actual auth dialog. If --headless, skip — the
  # checks above already prove the agent reads the theme without
  # blowing up. Visual confirmation is opt-in because it requires the
  # user's password.
  if [[ "$HEADLESS" -eq 1 ]]; then
    log "PASS [$theme_name] (headless)"
    return 0
  fi

  if [[ ! -x "$HELPER" || ! -x "$PKEXEC" ]]; then
    log "FAIL [$theme_name]: pkexec or keystone-approve-exec missing"
    log "  HELPER=$HELPER PKEXEC=$PKEXEC"
    return 1
  fi

  echo
  echo "  >>> A polkit dialog should appear for theme '$theme_name'."
  echo "      Check: background, border, text colors, gold accent on Authenticate."
  echo "      Cancel the dialog if you don't want to type your password —"
  echo "      a pkexec exit of 126/127 still proves render."
  echo

  local pkexec_start
  pkexec_start=$(date '+%Y-%m-%d %H:%M:%S')
  set +e
  "$PKEXEC" "$HELPER" --reason "polkit-theme-test ($theme_name)" -- ks activate /run/current-system
  local pkexec_exit=$?
  set -e
  log "  pkexec exited $pkexec_exit"

  # Re-check the journal for errors that surfaced *during* the dialog,
  # which is when the QML actually paints.
  agent_errors=$(journalctl --user -u "$AGENT_UNIT" --since "$pkexec_start" --no-pager 2>&1 \
    | grep -E 'qrc:/main\.qml.*Error|Cannot read property|QML.*ReferenceError|XMLHttpRequest.*forbidden' \
    || true)
  if [[ -n "$agent_errors" ]]; then
    log "FAIL [$theme_name]: agent reported QML errors during dialog:"
    printf '%s\n' "$agent_errors" | sed 's/^/    /' | tee -a "$LOG_FILE"
    return 1
  fi

  echo
  read -r -p "  Did the dialog render correctly for '$theme_name'? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) log "PASS [$theme_name] (user-confirmed)"; return 0 ;;
    *)           log "FAIL [$theme_name]: user reported visual problem"; return 1 ;;
  esac
}

# Snapshot current polkit.json once so multiple theme iterations don't
# clobber each other and a final restore reaches the user's real theme.
if [[ -f "$LIVE_THEME" && ! -f "$SNAPSHOT" ]]; then
  cp "$LIVE_THEME" "$SNAPSHOT"
  log "snapshot created at $SNAPSHOT"
fi

# Build the theme list.
declare -a THEMES
if [[ "$RUN_ALL" -eq 1 ]]; then
  if [[ ! -d "$THEMES_DIR" ]]; then
    echo "error: $THEMES_DIR not found — is keystone home-manager activated?" >&2
    exit 2
  fi
  while IFS= read -r line; do THEMES+=("$line"); done < <(
    find "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  )
elif [[ -n "$THEME_ARG" ]]; then
  THEMES=("$THEME_ARG")
else
  current="$(current_theme_name)"
  if [[ -z "$current" ]]; then
    echo "error: no active theme detected; pass --theme NAME or --all" >&2
    exit 2
  fi
  THEMES=("$current")
fi

log "==> run started (themes: ${THEMES[*]}, headless=$HEADLESS)"

failures=0
for theme in "${THEMES[@]}"; do
  if ! run_one "$theme"; then
    failures=$((failures + 1))
  fi
done

log "==> run finished: ${#THEMES[@]} tested, $failures failed"

# Trap restores the snapshot on exit — no manual restore needed.
exit "$failures"
