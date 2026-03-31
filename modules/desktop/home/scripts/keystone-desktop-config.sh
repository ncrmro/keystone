#!/usr/bin/env bash
# Shared helpers for persisting desktop state into nixos-config.

set -euo pipefail

keystone_config_repo_root() {
  if [[ -n "${KEYSTONE_SYSTEM_FLAKE:-}" ]]; then
    printf "%s\n" "$KEYSTONE_SYSTEM_FLAKE"
    return 0
  fi

  if [[ -n "${KEYSTONE_CONFIG_REPO:-}" ]]; then
    printf "%s\n" "$KEYSTONE_CONFIG_REPO"
    return 0
  fi

  if [[ -s /etc/keystone/system-flake ]]; then
    cat /etc/keystone/system-flake
    return 0
  fi

  local repo_root=""
  repo_root=$(find "$HOME/.keystone/repos" -maxdepth 2 -type d -name nixos-config 2>/dev/null | head -n1 || true)

  if [[ -z "$repo_root" ]]; then
    printf "Unable to locate nixos-config under ~/.keystone/repos\n" >&2
    return 1
  fi

  printf "%s\n" "$repo_root"
}

keystone_home_manager_host_file() {
  if [[ -n "${KEYSTONE_HOME_MANAGER_HOST_FILE:-}" ]]; then
    printf "%s\n" "$KEYSTONE_HOME_MANAGER_HOST_FILE"
    return 0
  fi

  local repo_root user_name host_name candidate
  repo_root=$(keystone_config_repo_root)
  user_name="${KEYSTONE_CONFIG_USER:-$USER}"
  host_name="${KEYSTONE_CONFIG_HOST:-$(hostname)}"
  candidate="${repo_root}/home-manager/${user_name}/${host_name}.nix"

  if [[ ! -f "$candidate" ]]; then
    printf "Unable to locate host home-manager file: %s\n" "$candidate" >&2
    return 1
  fi

  printf "%s\n" "$candidate"
}

keystone_write_managed_section() {
  local target_file="$1"
  local top_label="$2"
  local section_name="$3"
  local section_body=""
  section_body=$(cat)

  KEYSTONE_SECTION_BODY="$section_body" python3 - "$target_file" "$top_label" "$section_name" <<'PYCODE'
import pathlib
import re
import sys
import os

target = pathlib.Path(sys.argv[1])
top_label = sys.argv[2]
section_name = sys.argv[3]
section_body = os.environ["KEYSTONE_SECTION_BODY"].rstrip("\n")

doc = target.read_text()
top_start = f"  # BEGIN keystone-managed {top_label}"
top_end = f"  # END keystone-managed {top_label}"
section_start = f"  # BEGIN keystone-managed {section_name}"
section_end = f"  # END keystone-managed {section_name}"
section_block = f"{section_start}\n{section_body}\n{section_end}\n"

top_re = re.compile(
    rf"{re.escape(top_start)}\n(?P<body>.*?){re.escape(top_end)}\n?",
    re.S,
)
section_re = re.compile(
    rf"{re.escape(section_start)}\n.*?{re.escape(section_end)}\n?",
    re.S,
)

match = top_re.search(doc)
if match:
    top_body = match.group("body")
    if section_re.search(top_body):
        top_body = section_re.sub(section_block, top_body)
    else:
        if top_body and not top_body.endswith("\n"):
            top_body += "\n"
        top_body += section_block
    doc = doc[: match.start("body")] + top_body + doc[match.end("body") :]
else:
    insert = f"{top_start}\n{section_block}{top_end}\n"
    closing_index = doc.rfind("}")
    if closing_index == -1:
        raise SystemExit(f"Could not find closing brace in {target}")
    doc = doc[:closing_index].rstrip() + "\n\n" + insert + doc[closing_index:]

target.write_text(doc)
PYCODE
}

keystone_write_desktop_state_section() {
  local section_name="$1"
  local target_file=""

  target_file=$(keystone_home_manager_host_file)
  keystone_write_managed_section "$target_file" "desktop state" "$section_name"
}
