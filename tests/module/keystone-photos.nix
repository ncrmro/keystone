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

    method="GET"
    body=""
    url=""
    data_file=""
    output_file=""
    headers_file="''${TMP_DIR}/curl-headers.log"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -X)
          method="$2"
          shift 2
          ;;
        -d)
          body="$2"
          shift 2
          ;;
        -H)
          printf '%s\n' "$2" >>"$headers_file"
          shift 2
          ;;
        -F)
          printf '%s\n' "$2" >>"''${TMP_DIR}/curl-form.log"
          if [[ "$2" == assetData=@* ]]; then
            data_file="''${2#assetData=@}"
            data_file="''${data_file%%;*}"
          fi
          shift 2
          ;;
        -o)
          output_file="$2"
          shift 2
          ;;
        http://*|https://*)
          url="$1"
          shift
          ;;
        *)
          shift
          ;;
      esac
    done

    if [[ -n "$body" ]]; then
      printf '%s' "$body" >"''${TMP_DIR}/request.json"
    fi

    case "''${method} ''${url}" in
      "GET http://immich.local/api/people")
        cat <<'JSON'
    [
      {"id":"person-1","name":"Nick Romero","isFavorite":true},
      {"id":"person-2","name":"Someone Else","isFavorite":false}
    ]
    JSON
        ;;
      "GET http://immich.local/api/tags")
        cat <<'JSON'
    [
      {"id":"tag-1","name":"receipt","value":"receipt"},
      {"id":"tag-2","name":"family","value":"family"}
    ]
    JSON
        ;;
      "POST http://immich.local/api/search/smart")
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
              "dateTimeOriginal": "2026-03-01T12:00:00.000Z",
              "description": "Nick Romero business card",
              "city": "Austin",
              "state": "Texas",
              "country": "United States",
              "make": "Apple",
              "model": "iPhone 15 Pro",
              "lensModel": "Main Camera"
            },
            "people": [
              {"name":"Nick Romero"}
            ],
            "tags": [
              {"name":"receipt","value":"receipt"}
            ]
          }
        ]
      }
    }
    JSON
        ;;
      "POST http://immich.local/api/search/metadata")
        cat <<'JSON'
    {
      "assets": {
        "items": [
          {
            "id": "asset-2",
            "originalFileName": "IMG_2048.jpg",
            "originalPath": "/photos/trips/IMG_2048.jpg",
            "type": "IMAGE",
            "fileCreatedAt": "2026-02-01T12:00:00.000Z",
            "exifInfo": {
              "dateTimeOriginal": "2026-02-01T12:00:00.000Z",
              "description": "Family receipt in Austin",
              "city": "Austin",
              "state": "Texas",
              "country": "United States",
              "make": "Apple",
              "model": "iPhone 15 Pro",
              "lensModel": "Main Camera"
            },
            "people": [
              {"name":"Nick Romero"},
              {"name":"Someone Else"}
            ],
            "tags": [
              {"name":"receipt","value":"receipt"},
              {"name":"family","value":"family"}
            ]
          }
        ]
      }
    }
    JSON
        ;;
      "GET http://immich.local/api/assets/asset-1")
        cat <<'JSON'
    {
      "id": "asset-1",
      "originalFileName": "nick-romero-card.jpg",
      "originalPath": "/photos/cards/nick-romero-card.jpg",
      "type": "IMAGE"
    }
    JSON
        ;;
      "GET http://immich.local/api/assets/asset-1/original")
        [[ -n "$output_file" ]] || exit 1
        printf 'fake-binary-data\n' >"$output_file"
        ;;
      "GET http://immich.local/api/albums")
        if [[ -f "''${TMP_DIR}/album-created" ]]; then
          cat <<'JSON'
    [
      {"id":"album-1","albumName":"Screenshots - testuser"},
      {"id":"album-2","albumName":"New Screenshots - testuser"}
    ]
    JSON
        else
          cat <<'JSON'
    [
      {"id":"album-1","albumName":"Screenshots - testuser"}
    ]
    JSON
        fi
        ;;
      "POST http://immich.local/api/albums")
        touch "''${TMP_DIR}/album-created"
        printf '%s\n' "create-album" >>"''${TMP_DIR}/sync-events.log"
        cat <<'JSON'
    {"id":"album-2","albumName":"New Screenshots - testuser"}
    JSON
        ;;
      "POST http://immich.local/api/assets")
        if [[ -n "$data_file" ]]; then
          printf '%s\n' "upload $(basename "$data_file")" >>"''${TMP_DIR}/sync-events.log"
        fi
        cat <<'JSON'
    {"id":"uploaded-asset-1","status":"created"}
    JSON
        ;;
      "POST http://immich.local/api/albums/album-1/assets"|"POST http://immich.local/api/albums/album-2/assets")
        printf '%s\n' "album-add" >>"''${TMP_DIR}/sync-events.log"
        printf '{}\n'
        ;;
      "POST http://immich.local/api/tags/upsert")
        printf '%s\n' "tag-upsert" >>"''${TMP_DIR}/sync-events.log"
        printf '%s' "$body" >"''${TMP_DIR}/tag-upsert-request.json"
        cat <<'JSON'
    [
      {"id":"tag-source","value":"source:screenshot"},
      {"id":"tag-host","value":"host:test-host"},
      {"id":"tag-account","value":"account:testuser"}
    ]
    JSON
        ;;
      "POST http://immich.local/api/tags/tag-source/assets"|"POST http://immich.local/api/tags/tag-host/assets"|"POST http://immich.local/api/tags/tag-account/assets")
        printf '%s\n' "tag-asset" >>"''${TMP_DIR}/sync-events.log"
        printf '{}\n'
        ;;
      *)
        echo "Unexpected curl invocation: ''${method} ''${url}" >&2
        exit 1
        ;;
    esac
    EOF
          chmod +x "$TMP_DIR/curl"
        }

        create_fake_curl

        run_capture help env PATH="$TMP_DIR:$PATH" bash "$SCRIPT" --help
        assert_status help 0
        assert_contains help "keystone-photos — search and sync Immich assets from the terminal"
        assert_contains help "Credential discovery:"
        assert_contains help "keystone-photos preview <asset-id>"

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
        assert_contains person-search '"people": ['
        assert_contains person-search '"filename": "IMG_2048.jpg"'

        run_capture table-search env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" search --text "Nick Romero"
        assert_status table-search 0
        assert_contains table-search 'nick-romero-card.jpg'
        assert_contains table-search 'MATCH'

        run_capture advanced-search env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" search \
            --album "Screenshots - testuser" \
            --tag "receipt" \
            --country "United States" \
            --state "Texas" \
            --city "Austin" \
            --camera-make "Apple" \
            --camera-model "iPhone 15 Pro" \
            --lens-model "Main Camera" \
            --filename "IMG_" \
            --description "receipt" \
            --type image \
            --from 2026-02-01 \
            --to 2026-02-28 \
            --json
        assert_status advanced-search 0
        assert_contains advanced-search '"filename": "IMG_2048.jpg"'
        assert_contains advanced-search '"country": "United States"'
        assert_contains advanced-search '"make": "Apple"'

        if [[ "$(jq -r '.albumIds[0] // empty' "$TMP_DIR/request.json")" != "album-1" ]]; then
          echo "FAIL: advanced-search did not resolve album ids" >&2
          cat "$TMP_DIR/request.json" >&2 || true
          exit 1
        fi

        if [[ "$(jq -r '.tagIds[0] // empty' "$TMP_DIR/request.json")" != "tag-1" ]]; then
          echo "FAIL: advanced-search did not resolve tag ids" >&2
          cat "$TMP_DIR/request.json" >&2 || true
          exit 1
        fi

        run_capture people-list env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" people --json
        assert_status people-list 0
        assert_contains people-list '"name": "Nick Romero"'

        run_capture download env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          XDG_CACHE_HOME="$TMP_DIR/cache" \
          bash "$SCRIPT" download asset-1 --print-path
        assert_status download 0

        downloaded_path="$(tr -d '\n' < "$TMP_DIR/download.out")"
        if [[ ! -f "$downloaded_path" ]]; then
          echo "FAIL: download did not create the target file" >&2
          exit 1
        fi

        if ! grep -Fq 'fake-binary-data' "$downloaded_path"; then
          echo "FAIL: download did not write the expected asset payload" >&2
          cat "$downloaded_path" >&2 || true
          exit 1
        fi

        mkdir -p "$TMP_DIR/screenshots" "$TMP_DIR/state"
        printf 'fake png\n' >"$TMP_DIR/screenshots/screenshot-1.png"

        run_capture sync-first env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" sync-screenshots \
            --directory "$TMP_DIR/screenshots" \
            --album-name "New Screenshots - testuser" \
            --host-name "test-host" \
            --account-name "testuser" \
            --state-file "$TMP_DIR/state/sync.tsv"
        assert_status sync-first 0

        if ! grep -Fq 'upload screenshot-1.png' "$TMP_DIR/sync-events.log"; then
          echo "FAIL: sync-first did not upload the screenshot" >&2
          cat "$TMP_DIR/sync-events.log" >&2 || true
          exit 1
        fi

        if ! grep -Fq 'create-album' "$TMP_DIR/sync-events.log"; then
          echo "FAIL: sync-first did not create the album" >&2
          cat "$TMP_DIR/sync-events.log" >&2 || true
          exit 1
        fi

        if ! grep -Fq 'account:testuser' "$TMP_DIR/tag-upsert-request.json"; then
          echo "FAIL: sync-first did not request account tag upsert" >&2
          cat "$TMP_DIR/tag-upsert-request.json" >&2 || true
          exit 1
        fi

        sync_event_count_before="$(wc -l < "$TMP_DIR/sync-events.log")"

        run_capture sync-second env \
          PATH="$TMP_DIR:$PATH" \
          IMMICH_URL="http://immich.local" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          bash "$SCRIPT" sync-screenshots \
            --directory "$TMP_DIR/screenshots" \
            --album-name "New Screenshots - testuser" \
            --host-name "test-host" \
            --account-name "testuser" \
            --state-file "$TMP_DIR/state/sync.tsv"
        assert_status sync-second 0

        sync_event_count_after="$(wc -l < "$TMP_DIR/sync-events.log")"
        if [[ "$sync_event_count_before" != "$sync_event_count_after" ]]; then
          echo "FAIL: sync-second should have skipped the already uploaded file" >&2
          cat "$TMP_DIR/sync-events.log" >&2 || true
          exit 1
        fi

        touch "$out"
  ''
