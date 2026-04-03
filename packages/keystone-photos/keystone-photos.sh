#!/usr/bin/env bash
# keystone-photos — Immich-backed photo search for Keystone.

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
IMMICH_CONFIG_DIR="${XDG_CONFIG_HOME}/immich"

usage() {
  cat <<'EOF'
keystone-photos — search and sync Immich assets from the terminal

Usage:
  keystone-photos search [options]
  keystone-photos people [options]
  keystone-photos download <asset-id> [options]
  keystone-photos preview <asset-id>
  keystone-photos sync-screenshots [options]
  keystone-photos --help

Commands:
  search                Search Immich assets via metadata and smart search
  people                List known Immich people
  download              Download an Immich asset to the local cache or a path
  preview               Download an Immich asset and open a desktop preview
  sync-screenshots      Upload saved screenshots into a named Immich album

Options:
  --text QUERY          Generic smart-search query text
  --context QUERY       Additional contextual search text
  --ocr QUERY           OCR-focused search text
  --person NAME         Restrict results to an Immich person name (repeatable)
  --album NAME          Restrict results to an Immich album name (repeatable)
  --tag NAME            Restrict results to an Immich tag value (repeatable)
  --country NAME        Restrict results to a country
  --state NAME          Restrict results to a state or province
  --city NAME           Restrict results to a city
  --camera-make NAME    Restrict results to a camera make
  --camera-model NAME   Restrict results to a camera model
  --lens-model NAME     Restrict results to a lens model
  --filename TEXT       Restrict results to filenames containing TEXT
  --description TEXT    Restrict results to descriptions containing TEXT
  --type TYPE           Asset type: photo, screenshot, image, or video
  --kind KIND           Search preset; supported: business-card
  --from YYYY-MM-DD     Inclusive takenAfter date
  --to YYYY-MM-DD       Inclusive takenBefore date
  --start-date YYYY-MM-DD  Alias for --from
  --end-date YYYY-MM-DD    Alias for --to
  --limit N             Max results to request (default: 20)
  --json                Emit structured JSON
  -h, --help            Show this help

Credential discovery:
  1. IMMICH_URL and IMMICH_API_KEY environment variables
  2. ~/.config/immich/config.json with url/apiKey or IMMICH_URL/IMMICH_API_KEY keys
  3. ~/.config/immich/env or ~/.config/immich/.env with IMMICH_URL/IMMICH_API_KEY lines

Examples:
  keystone-photos search --text "acme"
  keystone-photos search --album "Screenshots - alice" --tag "receipt" --city "Austin"
  keystone-photos search --text "nick romero" --kind business-card
  keystone-photos search --person "Nick Romero" --type photo
  keystone-photos search --person "Nick Romero" --person "Alice Romero" --tag "family"
  keystone-photos people --json
  keystone-photos search --text "ks build" --type screenshot --from 2026-01-01 --to 2026-03-31
  keystone-photos search --text "acme" --json
  keystone-photos download asset-123 --print-path
  keystone-photos preview asset-123
  keystone-photos sync-screenshots --directory ~/Pictures --album-name "Screenshots - alice" --host-name workstation
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

trim_trailing_slash() {
  local value="$1"
  while [[ "$value" == */ ]]; do
    value="${value%/}"
  done
  printf '%s\n' "$value"
}

load_json_config_value() {
  local file="$1"
  local query="$2"
  [[ -f "$file" ]] || return 1
  jq -er "$query // empty" "$file" 2>/dev/null || return 1
}

load_env_config_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$file" \
    | tail -n1 \
    | sed 's/^[\"\x27]//; s/[\"\x27]$//' \
    | sed '/^[[:space:]]*$/d' \
    | head -n1
}

resolve_immich_url() {
  if [[ -n "${IMMICH_URL:-}" ]]; then
    trim_trailing_slash "$IMMICH_URL"
    return 0
  fi

  local config_json="${IMMICH_CONFIG_DIR}/config.json"
  local value=""

  value="$(load_json_config_value "$config_json" '.url' || true)"
  if [[ -n "$value" ]]; then
    trim_trailing_slash "$value"
    return 0
  fi
  value="$(load_json_config_value "$config_json" '.IMMICH_URL' || true)"
  if [[ -n "$value" ]]; then
    trim_trailing_slash "$value"
    return 0
  fi

  for file in "${IMMICH_CONFIG_DIR}/env" "${IMMICH_CONFIG_DIR}/.env"; do
    value="$(load_env_config_value "$file" 'IMMICH_URL' || true)"
    if [[ -n "$value" ]]; then
      trim_trailing_slash "$value"
      return 0
    fi
  done

  return 1
}

resolve_immich_api_key() {
  if [[ -n "${IMMICH_API_KEY:-}" ]]; then
    printf '%s\n' "$IMMICH_API_KEY"
    return 0
  fi

  local config_json="${IMMICH_CONFIG_DIR}/config.json"
  local value=""

  value="$(load_json_config_value "$config_json" '.apiKey' || true)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  value="$(load_json_config_value "$config_json" '.IMMICH_API_KEY' || true)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  for file in "${IMMICH_CONFIG_DIR}/env" "${IMMICH_CONFIG_DIR}/.env"; do
    value="$(load_env_config_value "$file" 'IMMICH_API_KEY' || true)"
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

resolve_credentials() {
  IMMICH_URL_RESOLVED="$(resolve_immich_url)" || true
  IMMICH_API_KEY_RESOLVED="$(resolve_immich_api_key)" || true

  [[ -n "${IMMICH_URL_RESOLVED:-}" ]] || die "missing Immich URL. Set IMMICH_URL or configure ~/.config/immich/config.json or ~/.config/immich/env."
  [[ -n "${IMMICH_API_KEY_RESOLVED:-}" ]] || die "missing Immich API key. Set IMMICH_API_KEY or configure ~/.config/immich/config.json or ~/.config/immich/env."
}

map_type() {
  case "$1" in
    "" ) printf '%s\n' "" ;;
    photo|image|screenshot) printf '%s\n' "IMAGE" ;;
    video) printf '%s\n' "VIDEO" ;;
    *)
      die "unsupported --type '$1'. Use photo, screenshot, image, or video."
      ;;
  esac
}

date_to_start() {
  printf '%sT00:00:00.000Z\n' "$1"
}

date_to_end() {
  printf '%sT23:59:59.999Z\n' "$1"
}

immich_api_get() {
  local path="$1"
  curl -fsS "${IMMICH_URL_RESOLVED}${path}" \
    -H "x-api-key: ${IMMICH_API_KEY_RESOLVED}" \
    -H "Accept: application/json"
}

immich_api_post() {
  local path="$1"
  local body="$2"
  curl -fsS -X POST "${IMMICH_URL_RESOLVED}${path}" \
    -H "x-api-key: ${IMMICH_API_KEY_RESOLVED}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$body"
}

immich_api_post_form() {
  local path="$1"
  shift
  curl -fsS -X POST "${IMMICH_URL_RESOLVED}${path}" \
    -H "x-api-key: ${IMMICH_API_KEY_RESOLVED}" \
    -H "Accept: application/json" \
    "$@"
}

immich_api_download() {
  local path="$1"
  local output_path="$2"
  curl -fsS "${IMMICH_URL_RESOLVED}${path}" \
    -H "x-api-key: ${IMMICH_API_KEY_RESOLVED}" \
    -H "Accept: application/octet-stream" \
    -o "$output_path"
}

resolve_person_ids() {
  local names_json
  names_json="$(printf '%s\n' "$@" | jq -R . | jq -cs 'map(select(length > 0))')"
  immich_api_get "/api/people" | jq -c --argjson names "$names_json" '
    def source_people:
      if type == "array" then .
      elif (.people? | type) == "array" then .people
      elif (.items? | type) == "array" then .items
      else []
      end;
    def wanted($candidate):
      ($names | map(ascii_downcase))
      | any(. == $candidate or ($candidate | contains(.)));
    [
      source_people[]
      | select(.name? != null and .id? != null)
      | . as $person
      | ($person.name | ascii_downcase) as $candidate
      | select(wanted($candidate))
      | $person.id
    ] | unique
  '
}

list_people() {
  immich_api_get "/api/people"
}

resolve_album_ids() {
  local names_json
  names_json="$(printf '%s\n' "$@" | jq -R . | jq -cs 'map(select(length > 0))')"
  immich_api_get "/api/albums" | jq -c --argjson names "$names_json" '
    def source_albums:
      if type == "array" then .
      elif (.albums? | type) == "array" then .albums
      elif (.items? | type) == "array" then .items
      else []
      end;
    def wanted($candidate):
      ($names | map(ascii_downcase))
      | any(. == $candidate or ($candidate | contains(.)));
    [
      source_albums[]
      | select(.albumName? != null and .id? != null)
      | . as $album
      | ($album.albumName | ascii_downcase) as $candidate
      | select(wanted($candidate))
      | $album.id
    ] | unique
  '
}

resolve_tag_ids() {
  local names_json
  names_json="$(printf '%s\n' "$@" | jq -R . | jq -cs 'map(select(length > 0))')"
  immich_api_get "/api/tags" | jq -c --argjson names "$names_json" '
    def source_tags:
      if type == "array" then .
      elif (.tags? | type) == "array" then .tags
      elif (.items? | type) == "array" then .items
      else []
      end;
    def tag_text:
      (.value // .name // "");
    def wanted($candidate):
      ($names | map(ascii_downcase))
      | any(. == $candidate or ($candidate | contains(.)));
    [
      source_tags[]
      | select(.id? != null)
      | . as $tag
      | ($tag | tag_text | ascii_downcase) as $candidate
      | select(($candidate | length) > 0 and wanted($candidate))
      | $tag.id
    ] | unique
  '
}

build_search_query() {
  local text="$1"
  local kind="$2"

  case "$kind" in
    "" )
      printf '%s\n' "$text"
      ;;
    business-card)
      printf '%s\n' "${text} business card contact card company email phone title website"
      ;;
    *)
      die "unsupported --kind '$kind'. Supported values: business-card."
      ;;
  esac
}

normalize_results() {
  local kind="$1"
  local raw_type="$2"
  local query_text="$3"
  local person_names_json="$4"
  local screenshot_mode="$5"
  local album_names_json="$6"
  local tag_names_json="$7"
  local context_query="$8"
  local ocr_query="$9"

  jq -c --arg baseUrl "$IMMICH_URL_RESOLVED" \
    --arg kind "$kind" \
    --arg rawType "$raw_type" \
    --arg queryText "$query_text" \
    --argjson personNames "$person_names_json" \
    --argjson albumNames "$album_names_json" \
    --argjson tagNames "$tag_names_json" \
    --arg contextQuery "$context_query" \
    --arg ocrQuery "$ocr_query" \
    --argjson screenshotMode "$screenshot_mode" '
    def source_assets:
      if (.assets? | type) == "object" then .assets.items // []
      elif (.assets? | type) == "array" then .assets
      else []
      end;
    def item_people:
      [.people[]?.name // empty] | unique;
    def item_tags:
      [.tags[]? | (.value // .name // empty)] | unique;
    def screenshot_name:
      ((.originalFileName // "") + " " + (.originalPath // ""))
      | ascii_downcase
      | test("screenshot|screen[ _-]?shot|capture");
    source_assets
    | map(
        {
          id,
          filename: (.originalFileName // ""),
          datetime: (
            .exifInfo.dateTimeOriginal
            // .fileCreatedAt
            // .createdAt
            // .updatedAt
            // ""
          ),
          assetType: (.type // ""),
          originalPath: (.originalPath // ""),
          description: (.exifInfo.description // .description // ""),
          location: {
            country: (.exifInfo.country // ""),
            state: (.exifInfo.state // ""),
            city: (.exifInfo.city // "")
          },
          camera: {
            make: (.exifInfo.make // ""),
            model: (.exifInfo.model // ""),
            lensModel: (.exifInfo.lensModel // "")
          },
          people: item_people,
          tags: item_tags,
          thumbnailUrl: ($baseUrl + "/api/assets/" + .id + "/thumbnail"),
          originalUrl: ($baseUrl + "/api/assets/" + .id + "/original"),
          match: {
            query: $queryText,
            context: $contextQuery,
            ocr: $ocrQuery,
            people: $personNames,
            albums: $albumNames,
            tags: $tagNames,
            kind: $kind,
            type: $rawType
          }
        }
      )
    | if $screenshotMode then map(select(screenshot_name)) else . end
  '
}

filter_results() {
  local json="$1"
  local filename_filter="$2"
  local description_filter="$3"

  printf '%s\n' "$json" | jq -c \
    --arg filenameFilter "$filename_filter" \
    --arg descriptionFilter "$description_filter" '
    map(
      select(
        (
          ($filenameFilter | length) == 0
          or ((.filename // "") | ascii_downcase | contains($filenameFilter | ascii_downcase))
        )
        and
        (
          ($descriptionFilter | length) == 0
          or ((.description // "") | ascii_downcase | contains($descriptionFilter | ascii_downcase))
        )
      )
    )
  '
}

print_results_table() {
  local json="$1"
  local count
  count="$(printf '%s\n' "$json" | jq 'length')"

  if [[ "$count" == "0" ]]; then
    echo "No results."
    return 0
  fi

  {
    printf 'ID\tDATE\tTYPE\tFILENAME\tMATCH\n'
    printf '%s\n' "$json" | jq -r '
      .[] |
      [
        .id,
        (.datetime // ""),
        (.assetType // ""),
        (.filename // ""),
        (
          [
            (.match.query // "" | select(length > 0) | "text=" + .),
            (.match.context // "" | select(length > 0) | "context=" + .),
            (.match.ocr // "" | select(length > 0) | "ocr=" + .),
            (.match.people[]? | "person=" + .),
            (.match.albums[]? | "album=" + .),
            (.match.tags[]? | "tag=" + .),
            (.match.kind // "" | select(length > 0) | "kind=" + .),
            (.match.type // "" | select(length > 0) | "type=" + .)
          ] | join(", ")
        )
      ] | @tsv
    '
  } | column -t -s $'\t'
}

asset_cache_dir() {
  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/keystone-photos/assets"
}

asset_metadata() {
  local asset_id="$1"
  immich_api_get "/api/assets/${asset_id}"
}

asset_filename_from_metadata() {
  jq -r '
    .originalFileName
    // (.originalPath | select(type == "string" and length > 0) | split("/") | last)
    // (.id + ".bin")
  '
}

asset_cache_path() {
  local asset_id="$1"
  local metadata="$2"
  local filename

  filename="$(printf '%s\n' "$metadata" | asset_filename_from_metadata)"
  filename="${filename//\//-}"
  filename="${filename//$'\n'/}"

  printf '%s/%s-%s\n' "$(asset_cache_dir)" "$asset_id" "$filename"
}

download_asset() {
  local asset_id="$1"
  local output_path="${2:-}"
  local metadata=""
  local cache_path=""
  local temp_output=""

  resolve_credentials
  metadata="$(asset_metadata "$asset_id")"

  if [[ -z "$output_path" ]]; then
    cache_path="$(asset_cache_path "$asset_id" "$metadata")"
  else
    cache_path="$output_path"
  fi

  mkdir -p "$(dirname "$cache_path")"

  if [[ ! -s "$cache_path" ]]; then
    temp_output="${cache_path}.tmp.$$"
    immich_api_download "/api/assets/${asset_id}/original" "$temp_output"
    mv "$temp_output" "$cache_path"
  fi

  printf '%s\n' "$cache_path"
}

open_preview_file() {
  local path="$1"

  if command -v sushi >/dev/null 2>&1; then
    setsid sushi "$path" >/dev/null 2>&1 &
    return 0
  fi

  if command -v loupe >/dev/null 2>&1; then
    setsid loupe "$path" >/dev/null 2>&1 &
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    setsid xdg-open "$path" >/dev/null 2>&1 &
    return 0
  fi

  die "no preview-capable opener found. Install sushi, loupe, or xdg-open."
}

state_has_hash() {
  local state_file="$1"
  local sha256="$2"
  [[ -f "$state_file" ]] || return 1
  grep -Fq -- "${sha256}"$'\t' "$state_file"
}

record_state() {
  local state_file="$1"
  local sha256="$2"
  local asset_id="$3"
  local path="$4"
  printf '%s\t%s\t%s\n' "$sha256" "$asset_id" "$path" >>"$state_file"
}

file_timestamp_utc() {
  local path="$1"
  date -u -d "@$(stat -c '%Y' "$path")" +'%Y-%m-%dT%H:%M:%S.000Z'
}

get_or_create_album_id() {
  local album_name="$1"
  local album_id=""

  album_id="$(immich_api_get "/api/albums" | jq -er --arg albumName "$album_name" '
    def source_albums:
      if type == "array" then .
      elif (.albums? | type) == "array" then .albums
      elif (.items? | type) == "array" then .items
      else []
      end;
    source_albums | map(select(.albumName == $albumName)) | first | .id // empty
  ' 2>/dev/null || true)"
  if [[ -n "$album_id" ]]; then
    printf '%s\n' "$album_id"
    return 0
  fi

  immich_api_post "/api/albums" "$(jq -cn --arg albumName "$album_name" '{ albumName: $albumName }')" \
    | jq -er '.id'
}

tag_asset() {
  local asset_id="$1"
  shift
  local tags_json upsert_json tag_id

  [[ "$#" -gt 0 ]] || return 0

  tags_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
  upsert_json="$(jq -cn --argjson tags "$tags_json" '{ tags: $tags }')"

  while IFS= read -r tag_id; do
    [[ -n "$tag_id" ]] || continue
    immich_api_post "/api/tags/${tag_id}/assets" "$(jq -cn --arg assetId "$asset_id" '{ ids: [$assetId] }')" >/dev/null
  done < <(immich_api_post "/api/tags/upsert" "$upsert_json" | jq -r '.[].id // empty')
}

cmd_search() {
  local text_query=""
  local context_query=""
  local ocr_query=""
  local country=""
  local state=""
  local city=""
  local camera_make=""
  local camera_model=""
  local lens_model=""
  local filename_filter=""
  local description_filter=""
  local raw_type=""
  local kind=""
  local from_date=""
  local to_date=""
  local limit=20
  local emit_json=false
  local -a person_names=()
  local -a album_names=()
  local -a tag_names=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --text)
        [[ $# -lt 2 ]] && die "--text requires a value."
        text_query="$2"
        shift 2
        ;;
      --context)
        [[ $# -lt 2 ]] && die "--context requires a value."
        context_query="$2"
        shift 2
        ;;
      --ocr)
        [[ $# -lt 2 ]] && die "--ocr requires a value."
        ocr_query="$2"
        shift 2
        ;;
      --person)
        [[ $# -lt 2 ]] && die "--person requires a value."
        person_names+=("$2")
        shift 2
        ;;
      --album)
        [[ $# -lt 2 ]] && die "--album requires a value."
        album_names+=("$2")
        shift 2
        ;;
      --tag)
        [[ $# -lt 2 ]] && die "--tag requires a value."
        tag_names+=("$2")
        shift 2
        ;;
      --country)
        [[ $# -lt 2 ]] && die "--country requires a value."
        country="$2"
        shift 2
        ;;
      --state)
        [[ $# -lt 2 ]] && die "--state requires a value."
        state="$2"
        shift 2
        ;;
      --city)
        [[ $# -lt 2 ]] && die "--city requires a value."
        city="$2"
        shift 2
        ;;
      --camera-make|--make)
        [[ $# -lt 2 ]] && die "$1 requires a value."
        camera_make="$2"
        shift 2
        ;;
      --camera-model|--model)
        [[ $# -lt 2 ]] && die "$1 requires a value."
        camera_model="$2"
        shift 2
        ;;
      --lens-model)
        [[ $# -lt 2 ]] && die "--lens-model requires a value."
        lens_model="$2"
        shift 2
        ;;
      --filename)
        [[ $# -lt 2 ]] && die "--filename requires a value."
        filename_filter="$2"
        shift 2
        ;;
      --description)
        [[ $# -lt 2 ]] && die "--description requires a value."
        description_filter="$2"
        shift 2
        ;;
      --type)
        [[ $# -lt 2 ]] && die "--type requires a value."
        raw_type="$2"
        shift 2
        ;;
      --kind)
        [[ $# -lt 2 ]] && die "--kind requires a value."
        kind="$2"
        shift 2
        ;;
      --from)
        [[ $# -lt 2 ]] && die "--from requires a value."
        from_date="$2"
        shift 2
        ;;
      --start-date)
        [[ $# -lt 2 ]] && die "--start-date requires a value."
        from_date="$2"
        shift 2
        ;;
      --to)
        [[ $# -lt 2 ]] && die "--to requires a value."
        to_date="$2"
        shift 2
        ;;
      --end-date)
        [[ $# -lt 2 ]] && die "--end-date requires a value."
        to_date="$2"
        shift 2
        ;;
      --limit)
        [[ $# -lt 2 ]] && die "--limit requires a value."
        limit="$2"
        shift 2
        ;;
      --json)
        emit_json=true
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        die "unknown option '$1'."
        ;;
    esac
  done

  [[
    -n "$text_query" || -n "$context_query" || -n "$ocr_query" || ${#person_names[@]} -gt 0 ||
    ${#album_names[@]} -gt 0 || ${#tag_names[@]} -gt 0 || -n "$country" || -n "$state" ||
    -n "$city" || -n "$camera_make" || -n "$camera_model" || -n "$lens_model" ||
    -n "$filename_filter" || -n "$description_filter" || -n "$raw_type" || -n "$from_date" || -n "$to_date"
  ]] || die "search requires at least one filter."
  [[ "$limit" =~ ^[0-9]+$ ]] || die "--limit must be a positive integer."
  [[ "$limit" -ge 1 ]] || die "--limit must be at least 1."

  if [[ "$kind" == "business-card" && -z "$text_query" && -z "$context_query" && -z "$ocr_query" ]]; then
    die "--kind business-card requires --text."
  fi

  resolve_credentials

  local person_ids='[]'
  local album_ids='[]'
  local tag_ids='[]'
  local person_names_json='[]'
  local album_names_json='[]'
  local tag_names_json='[]'

  if [[ ${#person_names[@]} -gt 0 ]]; then
    person_ids="$(resolve_person_ids "${person_names[@]}")"
    person_names_json="$(printf '%s\n' "${person_names[@]}" | jq -R . | jq -cs 'map(select(length > 0))')"
  fi
  if [[ ${#album_names[@]} -gt 0 ]]; then
    album_ids="$(resolve_album_ids "${album_names[@]}")"
    album_names_json="$(printf '%s\n' "${album_names[@]}" | jq -R . | jq -cs 'map(select(length > 0))')"
  fi
  if [[ ${#tag_names[@]} -gt 0 ]]; then
    tag_ids="$(resolve_tag_ids "${tag_names[@]}")"
    tag_names_json="$(printf '%s\n' "${tag_names[@]}" | jq -R . | jq -cs 'map(select(length > 0))')"
  fi

  local query_text="$text_query"
  if [[ -n "$context_query" ]]; then
    query_text="${query_text:+${query_text} }${context_query}"
  fi
  if [[ -n "$ocr_query" ]]; then
    query_text="${query_text:+${query_text} }${ocr_query}"
  fi
  query_text="$(build_search_query "$query_text" "$kind")"

  local raw_type_mapped=""
  raw_type_mapped="$(map_type "$raw_type")"
  if [[ "$kind" == "business-card" && -z "$raw_type_mapped" ]]; then
    raw_type_mapped="IMAGE"
  fi

  local taken_after="null"
  local taken_before="null"
  [[ -n "$from_date" ]] && taken_after="\"$(date_to_start "$from_date")\""
  [[ -n "$to_date" ]] && taken_before="\"$(date_to_end "$to_date")\""

  local request_body
  local screenshot_mode=false
  if [[ "$raw_type" == "screenshot" ]]; then
    screenshot_mode=true
  fi

  local use_smart_search=false
  if [[ -n "$query_text" ]]; then
    use_smart_search=true
  fi

  request_body="$(
    jq -cn \
      --arg query "$query_text" \
      --arg type "$raw_type_mapped" \
      --arg country "$country" \
      --arg state "$state" \
      --arg city "$city" \
      --arg make "$camera_make" \
      --arg model "$camera_model" \
      --arg lensModel "$lens_model" \
      --arg originalFileName "$filename_filter" \
      --arg description "$description_filter" \
      --argjson personIds "$person_ids" \
      --argjson albumIds "$album_ids" \
      --argjson tagIds "$tag_ids" \
      --argjson size "$limit" \
      --argjson takenAfter "$taken_after" \
      --argjson takenBefore "$taken_before" \
      '
      {
        size: $size,
        withExif: true
      }
      + (if ($query | length) > 0 then { query: $query } else {} end)
      + (if ($type | length) > 0 then { type: $type } else {} end)
      + (if ($country | length) > 0 then { country: $country } else {} end)
      + (if ($state | length) > 0 then { state: $state } else {} end)
      + (if ($city | length) > 0 then { city: $city } else {} end)
      + (if ($make | length) > 0 then { make: $make } else {} end)
      + (if ($model | length) > 0 then { model: $model } else {} end)
      + (if ($lensModel | length) > 0 then { lensModel: $lensModel } else {} end)
      + (if ($originalFileName | length) > 0 then { originalFileName: $originalFileName } else {} end)
      + (if ($description | length) > 0 then { description: $description } else {} end)
      + (if ($personIds | length) > 0 then { personIds: $personIds } else {} end)
      + (if ($albumIds | length) > 0 then { albumIds: $albumIds } else {} end)
      + (if ($tagIds | length) > 0 then { tagIds: $tagIds } else {} end)
      + (if $takenAfter != null then { takenAfter: $takenAfter } else {} end)
      + (if $takenBefore != null then { takenBefore: $takenBefore } else {} end)
      '
  )"

  local raw_response results_json
  if [[ "$use_smart_search" == true ]]; then
    raw_response="$(immich_api_post "/api/search/smart" "$request_body")"
  else
    raw_response="$(immich_api_post "/api/search/metadata" "$request_body")"
  fi

  results_json="$(
    printf '%s\n' "$raw_response" \
      | normalize_results \
          "$kind" \
          "$raw_type" \
          "$query_text" \
          "$person_names_json" \
          "$screenshot_mode" \
          "$album_names_json" \
          "$tag_names_json" \
          "$context_query" \
          "$ocr_query"
  )"
  results_json="$(filter_results "$results_json" "$filename_filter" "$description_filter")"

  if [[ "$emit_json" == true ]]; then
    printf '%s\n' "$results_json" | jq '.'
  else
    print_results_table "$results_json"
  fi
}

cmd_people() {
  local name_filter=""
  local emit_json=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name|--search)
        [[ $# -lt 2 ]] && die "$1 requires a value."
        name_filter="$2"
        shift 2
        ;;
      --json)
        emit_json=true
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage:
  keystone-photos people [options]

Options:
  --name TEXT          Filter people names containing TEXT
  --search TEXT        Alias for --name
  --json               Emit structured JSON
  -h, --help           Show this help
EOF
        return 0
        ;;
      *)
        die "unknown option '$1'."
        ;;
    esac
  done

  resolve_credentials

  local people_json
  people_json="$(
    list_people | jq --arg nameFilter "$name_filter" '
      def source_people:
        if type == "array" then .
        elif (.people? | type) == "array" then .people
        elif (.items? | type) == "array" then .items
        else []
        end;
      source_people
      | map({
          id,
          name: (.name // ""),
          isFavorite: (.isFavorite // false),
          faceCount: (
            if (.faces? | type) == "array" then (.faces | length)
            elif (.faceCount? != null) then .faceCount
            else 0
            end
          )
        })
      | map(
          select(
            ($nameFilter | length) == 0
            or (.name | ascii_downcase | contains($nameFilter | ascii_downcase))
          )
        )
      | sort_by(.name | ascii_downcase)
    '
  )"

  if [[ "$emit_json" == true ]]; then
    printf '%s\n' "$people_json" | jq '.'
    return 0
  fi

  if [[ "$(printf '%s\n' "$people_json" | jq 'length')" == "0" ]]; then
    echo "No people found."
    return 0
  fi

  {
    printf 'ID\tNAME\tFAVORITE\tFACES\n'
    printf '%s\n' "$people_json" | jq -r '
      .[] | [.id, .name, (.isFavorite | tostring), (.faceCount | tostring)] | @tsv
    '
  } | column -t -s $'\t'
}

cmd_download() {
  local asset_id="${1:-}"
  local output_path=""
  local print_path=false

  [[ -n "$asset_id" ]] || die "download requires an <asset-id>."
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        [[ $# -lt 2 ]] && die "--output requires a value."
        output_path="$2"
        shift 2
        ;;
      --print-path)
        print_path=true
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage:
  keystone-photos download <asset-id> [options]

Options:
  --output PATH         Write to a specific local path instead of the cache
  --print-path          Print the final file path
  -h, --help            Show this help
EOF
        return 0
        ;;
      *)
        die "unknown option '$1'."
        ;;
    esac
  done

  local final_path=""
  final_path="$(download_asset "$asset_id" "$output_path")"

  if [[ "$print_path" == true || -z "$output_path" ]]; then
    printf '%s\n' "$final_path"
  fi
}

cmd_preview() {
  local asset_id="${1:-}"
  [[ -n "$asset_id" ]] || die "preview requires an <asset-id>."

  local final_path=""
  final_path="$(download_asset "$asset_id")"
  open_preview_file "$final_path"
}

cmd_sync_screenshots() {
  local directory=""
  local album_name=""
  local host_name=""
  local account_name="${USER:-unknown}"
  local state_file=""
  local api_key_file=""
  local url_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --directory)
        [[ $# -lt 2 ]] && die "--directory requires a value."
        directory="$2"
        shift 2
        ;;
      --album-name)
        [[ $# -lt 2 ]] && die "--album-name requires a value."
        album_name="$2"
        shift 2
        ;;
      --host-name)
        [[ $# -lt 2 ]] && die "--host-name requires a value."
        host_name="$2"
        shift 2
        ;;
      --account-name)
        [[ $# -lt 2 ]] && die "--account-name requires a value."
        account_name="$2"
        shift 2
        ;;
      --state-file)
        [[ $# -lt 2 ]] && die "--state-file requires a value."
        state_file="$2"
        shift 2
        ;;
      --api-key-file)
        [[ $# -lt 2 ]] && die "--api-key-file requires a value."
        api_key_file="$2"
        shift 2
        ;;
      --url)
        [[ $# -lt 2 ]] && die "--url requires a value."
        url_override="$2"
        shift 2
        ;;
      -h|--help)
        cat <<'EOF'
Usage:
  keystone-photos sync-screenshots [options]

Options:
  --directory PATH       Screenshot directory to scan
  --album-name NAME      Immich album to create or reuse
  --host-name HOST       Host metadata value and host tag suffix
  --account-name NAME    Account metadata value and account tag suffix
  --state-file PATH      Local state file for uploaded hashes
  --api-key-file PATH    Read the Immich API key from a file
  --url URL              Immich base URL override
  -h, --help             Show this help
EOF
        return 0
        ;;
      *)
        die "unknown option '$1'."
        ;;
    esac
  done

  if [[ -n "$api_key_file" ]]; then
    [[ -f "$api_key_file" ]] || die "Immich API key file not found: $api_key_file"
    IMMICH_API_KEY="$(tr -d '\n' < "$api_key_file")"
    export IMMICH_API_KEY
  fi

  if [[ -n "$url_override" ]]; then
    IMMICH_URL="$url_override"
    export IMMICH_URL
  fi

  directory="${directory:-${KEYSTONE_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}}"
  album_name="${album_name:-Screenshots - ${account_name}}"
  host_name="${host_name:-$(hostname)}"
  state_file="${state_file:-${XDG_STATE_HOME:-$HOME/.local/state}/keystone-photos/screenshot-sync.tsv}"

  resolve_credentials

  if [[ ! -d "$directory" ]]; then
    echo "Screenshot directory does not exist, skipping: $directory" >&2
    return 0
  fi

  mkdir -p "$(dirname "$state_file")"
  touch "$state_file"

  local album_id
  album_id="$(get_or_create_album_id "$album_name")"

  local had_errors=0
  local found_files=0
  local file sha256 sha1 created_at modified_at upload_json asset_id status
  local -a screenshot_files=()
  local -a tags=(
    "source:screenshot"
    "host:${host_name}"
    "account:${account_name}"
  )

  shopt -s nullglob nocaseglob
  screenshot_files=("$directory"/*.png)
  shopt -u nullglob nocaseglob

  for file in "${screenshot_files[@]}"; do
    [[ -f "$file" ]] || continue
    found_files=1
    sha256="$(sha256sum "$file" | cut -d ' ' -f1)"
    if state_has_hash "$state_file" "$sha256"; then
      continue
    fi

    sha1="$(sha1sum "$file" | cut -d ' ' -f1)"
    created_at="$(file_timestamp_utc "$file")"
    modified_at="$created_at"

    if ! upload_json="$(
      immich_api_post_form \
        "/api/assets" \
        -H "x-immich-checksum: ${sha1}" \
        -F "assetData=@${file};type=image/png" \
        -F "deviceAssetId=${sha256}" \
        -F "deviceId=${host_name}" \
        -F "fileCreatedAt=${created_at}" \
        -F "fileModifiedAt=${modified_at}"
    )"; then
      echo "Failed to upload screenshot: $file" >&2
      had_errors=1
      continue
    fi

    asset_id="$(printf '%s' "$upload_json" | jq -r '.id // empty')"
    status="$(printf '%s' "$upload_json" | jq -r '.status // empty')"

    if [[ -z "$asset_id" && "$status" != "duplicate" ]]; then
      echo "Upload response missing asset id for: $file" >&2
      had_errors=1
      continue
    fi

    if [[ -n "$asset_id" ]]; then
      if ! immich_api_post "/api/albums/${album_id}/assets" "$(jq -cn --arg assetId "$asset_id" '{ ids: [$assetId] }')" >/dev/null; then
        echo "Failed to add screenshot to album '${album_name}': $file" >&2
        had_errors=1
        continue
      fi

      if ! tag_asset "$asset_id" "${tags[@]}"; then
        echo "Warning: failed to tag screenshot asset ${asset_id}" >&2
      fi
    fi

    record_state "$state_file" "$sha256" "${asset_id:-duplicate}" "$file"
  done

  if [[ "$found_files" -eq 0 ]]; then
    echo "No screenshots found in ${directory}" >&2
  fi

  if [[ "$had_errors" -ne 0 ]]; then
    return 1
  fi
}

main() {
  local command="${1:-}"
  case "$command" in
    ""|-h|--help)
      usage
      ;;
    search)
      shift
      cmd_search "$@"
      ;;
    people)
      shift
      cmd_people "$@"
      ;;
    download)
      shift
      cmd_download "$@"
      ;;
    preview)
      shift
      cmd_preview "$@"
      ;;
    sync-screenshots)
      shift
      cmd_sync_screenshots "$@"
      ;;
    *)
      die "unknown command '$command'."
      ;;
  esac
}

main "$@"
