{ pkgs }:
pkgs.runCommand "ks-help-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
    ];
  }
  ''
    export PATH="${
      pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ]
    }"

    cd ${../..}

    KS_SCRIPT="$PWD/packages/ks/ks.sh"
    TMP_DIR="$(mktemp -d)"

    cleanup() {
      local exit_code=$?
      rm -rf "$TMP_DIR"
      exit "$exit_code"
    }
    trap cleanup EXIT INT TERM

    run_capture() {
      local name="$1"
      shift

      local stdout_file="$TMP_DIR/$name.out"
      local stderr_file="$TMP_DIR/$name.err"
      local status_file="$TMP_DIR/$name.status"

      if ${pkgs.bash}/bin/bash "$KS_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file"; then
        printf '0\n' >"$status_file"
      else
        printf '%s\n' "$?" >"$status_file"
      fi
    }

    assert_status() {
      local name="$1"
      local expected="$2"
      local actual
      actual="$(cat "$TMP_DIR/$name.status")"

      if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $name exited with $actual, expected $expected" >&2
        echo "--- stdout ---" >&2
        cat "$TMP_DIR/$name.out" >&2 || true
        echo "--- stderr ---" >&2
        cat "$TMP_DIR/$name.err" >&2 || true
        exit 1
      fi
    }

    assert_contains() {
      local name="$1"
      local pattern="$2"
      local combined="$TMP_DIR/$name.combined"

      cat "$TMP_DIR/$name.out" "$TMP_DIR/$name.err" >"$combined"
      if ! grep -Fq -- "$pattern" "$combined"; then
        echo "FAIL: $name missing pattern: $pattern" >&2
        echo "--- combined output ---" >&2
        cat "$combined" >&2 || true
        exit 1
      fi
    }

    run_capture main-long --help
    assert_status main-long 0
    assert_contains main-long "Usage: ks <command> [options]"
    assert_contains main-long "help [command]"

    run_capture main-short -h
    assert_status main-short 0
    assert_contains main-short "Usage: ks <command> [options]"

    run_capture help-root help
    assert_status help-root 0
    assert_contains help-root 'Use "ks help <command>" for command-specific help.'

    for command in approve build update switch sync-host-keys agent doctor grafana docs photos; do
      run_capture "help-$command" help "$command"
      assert_status "help-$command" 0
      assert_contains "help-$command" "Usage: ks $command"
      assert_contains "help-$command" "Examples:"

      run_capture "$command-long" "$command" --help
      assert_status "$command-long" 0
      assert_contains "$command-long" "Usage: ks $command"

      run_capture "$command-short" "$command" -h
      assert_status "$command-short" 0
      assert_contains "$command-short" "Usage: ks $command"
    done

    run_capture help-grafana-dashboards help grafana dashboards
    assert_status help-grafana-dashboards 0
    assert_contains help-grafana-dashboards "Usage: ks grafana dashboards <apply|export> [uid]"

    run_capture docs-topic docs --help
    assert_status docs-topic 0
    assert_contains docs-topic "Topics:"
    assert_contains docs-topic "ks docs terminal/projects.md"

    run_capture grafana-dashboards-long grafana dashboards --help
    assert_status grafana-dashboards-long 0
    assert_contains grafana-dashboards-long "Subcommands:"
    assert_contains grafana-dashboards-long "export <uid>"

    run_capture grafana-dashboards-short grafana dashboards -h
    assert_status grafana-dashboards-short 0
    assert_contains grafana-dashboards-short "Usage: ks grafana dashboards <apply|export> [uid]"

    run_capture unknown-command unknown-command
    assert_status unknown-command 1
    assert_contains unknown-command "Error: Unknown command 'unknown-command'"

    run_capture build-bad-flag build --bad-flag
    assert_status build-bad-flag 1
    assert_contains build-bad-flag "Error: Unknown option '--bad-flag'"

    run_capture help-unknown help unknown-topic
    assert_status help-unknown 1
    assert_contains help-unknown "Error: Unknown help topic 'unknown-topic'"

    run_capture grafana-missing grafana dashboards
    assert_status grafana-missing 1
    assert_contains grafana-missing "Error: Missing grafana dashboards action"

    touch "$out"
  ''
