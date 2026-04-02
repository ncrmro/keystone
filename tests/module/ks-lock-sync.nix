{ pkgs }:
pkgs.runCommand "ks-lock-sync"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export PATH="$PWD/bin:${
      pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ]
    }"

    mkdir -p "$PWD/bin" "$PWD/repos/no-drift" "$PWD/repos/needs-rebase"

    cat > "$PWD/bin/git" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ "$1" != "-C" ]]; then
      echo "expected git -C <path> ..." >&2
      exit 1
    fi

    repo_path="$2"
    shift 2

    case "$1" in
      symbolic-ref)
        printf 'main\n'
        ;;
      rev-parse)
        printf 'origin/main\n'
        ;;
      rev-list)
        state_file="$repo_path/.rev-list-state"
        if [[ ! -f "$state_file" ]]; then
          printf '0\t0\n'
          exit 0
        fi

        state="$(cat "$state_file")"
        case "$state" in
          no-drift)
            printf '0\t0\n'
            ;;
          needs-rebase-before)
            printf '1\t0\n'
            ;;
          needs-rebase-after)
            printf '0\t0\n'
            ;;
          *)
            echo "unexpected rev-list state: $state" >&2
            exit 1
            ;;
        esac
        ;;
      pull)
        if [[ "$2" != "--rebase" ]]; then
          echo "expected git pull --rebase" >&2
          exit 1
        fi
        printf '%s\n' needs-rebase-after > "$repo_path/.rev-list-state"
        ;;
      push)
        echo "push should not run in this regression test" >&2
        exit 1
        ;;
      *)
        echo "unexpected git invocation: $*" >&2
        exit 1
        ;;
    esac
    EOF
    chmod +x "$PWD/bin/git"

    printf '%s\n' no-drift > "$PWD/repos/no-drift/.rev-list-state"
    printf '%s\n' needs-rebase-before > "$PWD/repos/needs-rebase/.rev-list-state"

    sed '/# --- Main dispatch ---/,$d' "$REPO_ROOT/packages/ks/ks.sh" > "$PWD/ks-functions.sh"

    cat > "$PWD/test.sh" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    source "$PWD/ks-functions.sh"
    run_with_warning_filter() {
      "$@"
    }

    push_repo_for_lock "$PWD/repos/no-drift" "ncrmro/agenix-secrets" >"$PWD/no-drift.out" 2>"$PWD/no-drift.err"
    if [[ -s "$PWD/no-drift.err" ]]; then
      echo "unexpected stderr for no-drift case" >&2
      cat "$PWD/no-drift.err" >&2
      exit 1
    fi

    push_repo_for_lock "$PWD/repos/needs-rebase" "ncrmro/agenix-secrets" >"$PWD/rebase.out" 2>"$PWD/rebase.err"
    grep -F "Rebasing ncrmro/agenix-secrets onto origin/main..." "$PWD/rebase.out" >/dev/null
    if [[ -s "$PWD/rebase.err" ]]; then
      echo "unexpected stderr for rebase case" >&2
      cat "$PWD/rebase.err" >&2
      exit 1
    fi
    EOF
    chmod +x "$PWD/test.sh"

    "$PWD/test.sh"

    touch "$out"
  ''
