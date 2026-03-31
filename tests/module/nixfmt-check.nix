{ pkgs }:
pkgs.runCommand "nixfmt-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      nixfmt
    ];
  }
  ''
    set -euo pipefail

    export HOME="$PWD/home"
    mkdir -p "$HOME"

    cd ${../..}

    find flake.nix modules packages tests bin conventions docs specs \
      -name '*.nix' -print0 \
      | xargs -0 --no-run-if-empty nixfmt --check

    touch "$out"
  ''
