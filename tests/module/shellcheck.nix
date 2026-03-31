{ pkgs }:
pkgs.runCommand "shellcheck-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      shellcheck
    ];
  }
  ''
    set -euo pipefail

    export HOME="$PWD/home"
    mkdir -p "$HOME"

    cd ${../..}

    find bin modules packages tests .deepwork \
      \( -path 'modules/terminal/claude-code/update.sh' -o -path 'modules/terminal/scripts/keystone-sync-agent-assets.sh' \) -prune \
      -o \( -name '*.sh' -o -name '*.bash' \) -print0 \
      | xargs -0 --no-run-if-empty shellcheck -S error

    touch "$out"
  ''
