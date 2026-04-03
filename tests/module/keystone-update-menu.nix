{
  pkgs,
  lib,
}:
pkgs.runCommand "test-keystone-update-menu"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      git
      gnugrep
      gnused
      jq
      zsh
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export XDG_RUNTIME_DIR="$PWD/runtime"
    export KEYSTONE_SYSTEM_FLAKE="$PWD/nixos-config"
    export KEYSTONE_CONFIG_HOST="mox"
    export PATH="$PWD/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.git
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.zsh
      ]
    }"

    mkdir -p "$HOME/.local/bin" "$XDG_RUNTIME_DIR" "$KEYSTONE_SYSTEM_FLAKE" "$PWD/bin"

    cat > "$PWD/bin/keystone-update-menu" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/modules/desktop/home/scripts/keystone-update-menu.sh" "$@"
    EOF
    chmod +x "$PWD/bin/keystone-update-menu"
    ln -s "$PWD/bin/keystone-update-menu" "$HOME/.local/bin/keystone-update-menu"

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

    cat > "$PWD/bin/notify-send" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "$*" > "$XDG_RUNTIME_DIR/notify-send.txt"
    exit 0
    EOF
    chmod +x "$PWD/bin/notify-send"

    cat > "$PWD/bin/xdg-open" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "$*" > "$XDG_RUNTIME_DIR/xdg-open.txt"
    exit 0
    EOF
    chmod +x "$PWD/bin/xdg-open"

    cat > "$PWD/bin/uname" <<'EOF'
    #!${pkgs.bash}/bin/bash
    if [[ "''${1:-}" == "-n" ]]; then
      printf 'mox\n'
      exit 0
    fi
    exec ${pkgs.coreutils}/bin/uname "$@"
    EOF
    chmod +x "$PWD/bin/uname"

    cat > "$PWD/bin/gh" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "''${1:-}" != "api" ]]; then
      echo "Unexpected gh invocation: $*" >&2
      exit 1
    fi

    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -H)
          shift 2
          ;;
        *)
          break
          ;;
      esac
    done

    case "$1" in
      repos/ncrmro/keystone/releases/latest)
        cat <<'JSON'
    {
      "tag_name": "v0.8.0",
      "name": "v0.8.0",
      "html_url": "https://github.com/ncrmro/keystone/releases/tag/v0.8.0",
      "published_at": "2026-04-01T10:00:00Z",
      "body": "## Changes\n- Added Walker update menu"
    }
    JSON
        ;;
      repos/ncrmro/keystone/commits/v0.8.0)
        cat <<'JSON'
    {
      "sha": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
    JSON
        ;;
      *)
        echo "Unexpected gh api path: $1" >&2
        exit 1
        ;;
    esac
    EOF
    chmod +x "$PWD/bin/gh"

    cat > "$PWD/bin/git" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "''${1:-}" == "-C" ]]; then
      repo="$2"
      shift 2
    else
      repo="$PWD"
    fi

    case "$*" in
      "status --porcelain --untracked-files=normal")
        if [[ -f "$XDG_RUNTIME_DIR/dirty" ]]; then
          printf ' M flake.nix\n'
        fi
        ;;
      "tag --points-at aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        printf 'v0.7.0\n'
        ;;
      "tag --points-at bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        printf 'v0.8.0\n'
        ;;
      "cat-file -e aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa^{commit}"|"cat-file -e bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb^{commit}")
        exit 0
        ;;
      "merge-base --is-ancestor bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        exit 1
        ;;
      *)
        echo "Unexpected git invocation in $repo: $*" >&2
        exit 1
        ;;
    esac
    EOF
    chmod +x "$PWD/bin/git"

    cat > "$PWD/bin/nix" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "''${1:-}" == "eval" && "''${2:-}" == "--json" && "''${3:-}" == "--file" ]]; then
      cat <<'JSON'
    {
      "mox": { "hostname": "mox" }
    }
    JSON
      exit 0
    fi

    if [[ "''${1:-}" == "flake" && "''${2:-}" == "update" ]]; then
      printf '%s\n' "$*" > "$XDG_RUNTIME_DIR/nix-flake-update.txt"
      exit 0
    fi

    echo "Unexpected nix invocation: $*" >&2
    exit 1
    EOF
    chmod +x "$PWD/bin/nix"

    cat > "$KEYSTONE_SYSTEM_FLAKE/flake.lock" <<'EOF'
    {
      "nodes": {
        "root": {
          "inputs": {
            "keystone": "keystone",
            "nixpkgs": "nixpkgs"
          }
        },
        "keystone": {
          "locked": {
            "type": "github",
            "owner": "ncrmro",
            "repo": "keystone",
            "rev": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          }
        },
        "nixpkgs": {
          "locked": {
            "type": "github",
            "owner": "NixOS",
            "repo": "nixpkgs",
            "rev": "cccccccccccccccccccccccccccccccccccccccc"
          }
        }
      }
    }
    EOF

    cat > "$KEYSTONE_SYSTEM_FLAKE/hosts.nix" <<'EOF'
    {}
    EOF

    entries_json="$(keystone-update-menu entries-json)"
    printf '%s\n' "$entries_json" | jq -e '
      length == 3
      and any(.[]; .Text == "Current: v0.7.0" and (.Subtext | contains("newer Keystone release")))
      and any(.[]; .Text == "Latest: v0.8.0" and .Value == "open-release-page\thttps://github.com/ncrmro/keystone/releases/tag/v0.8.0")
      and any(.[]; .Text == "Update current host" and .Value == "run-update")
    ' >/dev/null

    preview_notes="$(keystone-update-menu preview-release-notes)"
    printf '%s\n' "$preview_notes" | grep -F 'Added Walker update menu' >/dev/null

    keystone-update-menu dispatch $'open-release-page\thttps://github.com/ncrmro/keystone/releases/tag/v0.8.0'
    grep -F 'https://github.com/ncrmro/keystone/releases/tag/v0.8.0' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null

    keystone-update-menu dispatch 'run-update'
    grep -F -- 'ghostty --title keystone-os-update -e bash -lc' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null
    grep -F -- "nix flake update keystone --flake $KEYSTONE_SYSTEM_FLAKE && ks update mox" "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null
    grep -F 'Relocking keystone' "$XDG_RUNTIME_DIR/notify-send.txt" >/dev/null

    touch "$XDG_RUNTIME_DIR/dirty"
    dirty_json="$(keystone-update-menu entries-json)"
    printf '%s\n' "$dirty_json" | jq -e '
      any(.[]; .Text == "Update unavailable" and (.Subtext | contains("uncommitted changes")))
    ' >/dev/null

    rm -f "$XDG_RUNTIME_DIR/detach-command.txt"
    keystone-update-menu dispatch 'run-update'
    [[ ! -f "$XDG_RUNTIME_DIR/detach-command.txt" ]]
    grep -F 'uncommitted changes' "$XDG_RUNTIME_DIR/notify-send.txt" >/dev/null

    touch "$out"
  ''
