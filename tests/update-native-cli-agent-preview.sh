#!/usr/bin/env bash

set -euo pipefail

repo_root="${KEYSTONE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
output_root="${1:-$repo_root/tests/fixtures/agents}"
manifest_path="$(mktemp)"

cleanup() {
  rm -f "$manifest_path"
}
trap cleanup EXIT

cat > "$manifest_path" <<EOF
{
  "developmentMode": false,
  "repoCheckout": "$repo_root",
  "archetype": "keystone-system-host",
  "resolvedCapabilities": ["ks", "notes", "project", "engineer", "product", "project-manager"],
  "publishedCommands": ["ks", "ks.notes", "ks.projects", "ks.engineer", "ks.product", "ks.pm"],
  "repos": ["ncrmro/keystone"],
  "agents": {}
}
EOF

rm -rf "$output_root"
mkdir -p "$output_root"

HOME="$output_root" KEYSTONE_AGENT_ASSETS_MANIFEST="$manifest_path" \
  bash "$repo_root/modules/terminal/scripts/keystone-sync-agent-assets.sh"
