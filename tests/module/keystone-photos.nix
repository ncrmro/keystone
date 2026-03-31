{ pkgs, lib }:
pkgs.runCommand "keystone-photos-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      jq
      util-linux
    ];
  }
  ''
        export PATH="${
          pkgs.lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.util-linux
          ]
        }"

        cd ${../..}

        SCRIPT="$PWD/packages/keystone-photos/keystone-photos.sh"
        TMP_DIR="$(mktemp -d)"

        cleanup() {
          local exit_code=$?
          rm -rf "$TMP_DIR"
          exit "$exit_code"
        }
        trap cleanup EXIT INT TERM

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

        run_capture() {
          local name="$1"
          shift

          local stdout_file="$TMP_DIR/$name.out"
          local stderr_file="$TMP_DIR/$name.err"
          local status_file="$TMP_DIR/$name.status"

          if "$@" >"$stdout_file" 2>"$stderr_file"; then
            printf '0\n' >"$status_file"
          else
            printf '%s\n' "$?" >"$status_file"
          fi
        }

        create_fake_curl() {
          cat >"$TMP_DIR/curl" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    args="$*"
    request_file="''${TMP_DIR}/request.json"

    if [[ "$args" == *"/api/people"* ]]; then
      cat <<'JSON'
    [
      {"id":"person-1","name":"Nick Romero"},
      {"id":"person-2","name":"Someone Else"}
    ]
    JSON
      exit 0
    fi

    body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -d)
          body="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    printf '%s' "$body" >"$request_file"

    cat <<'JSON'
    {
      "assets": {
        "items": [
          {
            "id": "asset-1",
            "originalFileName": "nick-romero-card.jpg",
            "originalPath": "/photos/cards/nick-romero-card.jpg",
            "type": "IMAGE",
            "fileCreatedAt": "2026-03-01T12:00:00.000Z",
            "exifInfo": {
              "dateTimeOriginal": "2026-03-01T12:00:00.000Z"
            }
          }
        ]
      }
    }
    JSON
    EOF
          chmod +x "$TMP_DIR/curl"
        }

        create_fake_curl

        run_capture help env PATH="$TMP_DIR:$PATH" bash "$SCRIPT" --help
        assert_status help 0
        assert_contains help "keystone-photos — search Immich assets from the terminal"
        assert_contains help "Credential discovery:"

        run_capture missing-creds env PATH="$TMP_DIR:$PATH" bash "$SCRIPT" search --text acme
        assert_status missing-creds 1
        assert_contains missing-creds "missing Immich URL"

        run_capture json-search env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" search --text "Nick Romero" --kind business-card --json
        assert_status json-search 0
        assert_contains json-search '"filename": "nick-romero-card.jpg"'
        assert_contains json-search '"kind": "business-card"'

        if ! grep -Fq 'business card' "$TMP_DIR/request.json"; then
          echo "FAIL: business-card request was not expanded" >&2
          cat "$TMP_DIR/request.json" >&2 || true
          exit 1
        fi

        run_capture person-search env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" search --person "Nick Romero" --json
        assert_status person-search 0
        assert_contains person-search '"person": "Nick Romero"'
        assert_contains person-search '"filename": "nick-romero-card.jpg"'

        run_capture table-search env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" search --text "Nick Romero"
        assert_status table-search 0
        assert_contains table-search 'nick-romero-card.jpg'
        assert_contains table-search 'MATCH'

        touch "$out"
  ''
