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
  "repoCheckout": null,
  "fallbackConventionsDir": "$repo_root/conventions",
  "fallbackTemplatesDir": "$repo_root/modules/terminal/agent-assets",
  "archetype": "keystone-system-host",
  "resolvedCapabilities": ["ks", "notes", "project"],
  "publishedCommands": ["ks", "ks.notes", "ks.projects"],
  "repos": ["ncrmro/keystone"],
  "agents": {
    "architect": {
      "host": "keystone",
      "archetype": "engineer",
      "notesPath": "/home/agent-architect/notes",
      "mcpServers": {
        "deepwork": {
          "command": "/nix/store/example-deepwork/bin/deepwork",
          "args": ["serve", "--path", ".", "--platform", "claude"]
        }
      }
    }
  }
}
EOF

rm -rf "$output_root"
mkdir -p "$output_root"

KEYSTONE_AGENT_ASSETS_MANIFEST="$manifest_path" \
  bash "$repo_root/modules/terminal/scripts/keystone-sync-agent-assets.sh" \
  --output-root "$output_root" \
  --conventions-link-base "/repo/conventions"
