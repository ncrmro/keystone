{
  pkgs,
  lib,
}:
pkgs.runCommand "test-keystone-hardware-menu"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "FAIL: $*" >&2
      exit 1
    }

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export XDG_RUNTIME_DIR="$PWD/runtime"
    export PATH="$PWD/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
      ]
    }"

    mkdir -p "$HOME/.local/bin" "$XDG_RUNTIME_DIR" "$PWD/bin"

    cat > "$PWD/bin/keystone-hardware-menu" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/modules/desktop/home/scripts/keystone-hardware-menu.sh" "$@"
    EOF
    chmod +x "$PWD/bin/keystone-hardware-menu"
    ln -s "$PWD/bin/keystone-hardware-menu" "$HOME/.local/bin/keystone-hardware-menu"

    cat > "$PWD/bin/keystone-detach" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "$*" > "$XDG_RUNTIME_DIR/detach-command.txt"
    exit 0
    EOF
    chmod +x "$PWD/bin/keystone-detach"

    cat > "$PWD/bin/ghostty" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exit 0
    EOF
    chmod +x "$PWD/bin/ghostty"

    cat > "$PWD/bin/ks" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exit 0
    EOF
    chmod +x "$PWD/bin/ks"

    preview_enroll="$(keystone-hardware-menu preview enroll)"
    printf '%s\n' "$preview_enroll" \
      | grep -F 'ks hardware enroll fido2' >/dev/null \
      || fail "preview must show the canonical ks hardware enroll command"

    keystone-hardware-menu dispatch $'enroll-fido2\tEnroll hardware key\t'

    grep -F 'ghostty' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null \
      || fail "dispatch must launch ghostty via keystone-detach"
    grep -F 'exec ' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null \
      || fail "dispatch must execute the hardware command directly"
    grep -F ' hardware enroll fido2' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null \
      || fail "dispatch must invoke the bare ks hardware enroll command"
    if grep -F 'approve --reason' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null; then
      fail "dispatch must not hardcode ks approve once the command self-brokers"
    fi

    touch "$out"
  ''
