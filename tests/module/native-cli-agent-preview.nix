{ pkgs }:
pkgs.runCommand "native-cli-agent-preview-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      diffutils
      gnugrep
      jq
      yq-go
    ];
  }
  ''
    set -euo pipefail

    export HOME="$PWD/home"
    mkdir -p "$HOME"

    actual="$PWD/actual"

    KEYSTONE_REPO_ROOT="${../..}" \
      ${pkgs.bash}/bin/bash ${../update-native-cli-agent-preview.sh} "$actual"

    diff -ru ${../fixtures/agents} "$actual"

    touch "$out"
  ''
