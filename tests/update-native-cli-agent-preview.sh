#!/usr/bin/env bash

set -euo pipefail

repo_root="${KEYSTONE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
output_root="${1:-$repo_root/tests/fixtures/native-cli-agents-preview}"
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
    "drago": {
      "host": "keystone",
      "archetype": "engineer",
      "notesPath": "/home/agent-drago/notes",
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

rm -f \
  "$output_root/.keystone/AGENTS.md" \
  "$output_root/.keystone/repos/AGENTS.md" \
  "$output_root/.claude/CLAUDE.md" \
  "$output_root/.gemini/GEMINI.md" \
  "$output_root/.codex/AGENTS.md" \
  "$output_root/.config/opencode/AGENTS.md"

rm -rf \
  "$output_root/.claude/commands" \
  "$output_root/.claude/skills" \
  "$output_root/.gemini/commands" \
  "$output_root/.codex/skills" \
  "$output_root/.config/opencode/commands" \
  "$output_root/.config/opencode/skills" \
  "$output_root/.keystone"
