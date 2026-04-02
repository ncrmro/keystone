#!/usr/bin/env bash
# Sync generated Keystone agent assets from the current profile manifest.
# See conventions/code.shell-scripts.md

set -euo pipefail

manifest_path="${KEYSTONE_AGENT_ASSETS_MANIFEST:-$HOME/.config/keystone/agent-assets.json}"

usage() {
  cat <<'EOF'
Usage: keystone-sync-agent-assets

Refresh generated Keystone agent assets for the current user from the current
profile manifest. This is the development-mode refresh path for instruction
files, curated commands, Codex skills, and native CLI agent definitions.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$manifest_path" ]]; then
  echo "Error: agent asset manifest not found at $manifest_path" >&2
  exit 1
fi

json_get() {
  local filter="$1"
  jq -r "$filter" "$manifest_path"
}

json_get_lines() {
  local filter="$1"
  jq -r "$filter | .[]" "$manifest_path"
}

yaml_quote() {
  jq -Rn --arg value "$1" '$value'
}

write_file() {
  local target="$1"
  local content="$2"
  local target_dir
  local tmp

  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  rm -f "$target"

  tmp="$(mktemp "$target.tmp.XXXXXX")"
  printf '%s' "$content" > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$target"
}

append_file_content() {
  local output_file="$1"
  local source_file="$2"

  printf '\n---\n\n' >> "$output_file"
  cat "$source_file" >> "$output_file"
}

render_template() {
  local template_path="$1"
  local content

  content="$(cat "$template_path")"
  content="${content//__CAPABILITIES__/$capabilities_display}"
  content="${content//__DEVELOPMENT_MODE__/$development_mode_display}"
  content="${content//__PUBLISHED_COMMANDS__/$published_commands_display}"
  content="${content//__ALLOWED_ROUTES__/$ks_allowed_routes}"

  printf '%s\n' "$content"
}

render_frontmatter() {
  local name="$1"
  local description="$2"
  local argument_hint="$3"
  local display_name="$4"

  cat <<EOF
---
name: $(yaml_quote "$name")
description: $(yaml_quote "$description")
argument-hint: $(yaml_quote "$argument_hint")
display-name: $(yaml_quote "$display_name")
---
EOF
}

render_skill_md() {
  local name="$1"
  local description="$2"
  local body="$3"

  cat <<EOF
---
name: $name
description: "$(printf '%s' "$description" | sed 's/"/\\"/g')"
---

$body
EOF
}

codex_skill_name() {
  printf '%s' "$1" | tr '.' '-'
}

render_codex_skill_body() {
  local command_body="$1"
  local skill_name="$2"
  local skill_token="\$${skill_name}"

  cat <<EOF
$command_body

## Codex skill invocation

Use this skill when the user invokes \`${skill_token}\` or asks for this workflow implicitly.
Interpret \`\$ARGUMENTS\` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
EOF
}

write_gemini_command() {
  local rel_path="$1"
  local description="$2"
  local body="$3"

  write_file "$HOME/.gemini/commands/$rel_path" \
    "description = $(yaml_quote "$description")"$'\n'"prompt = $(yaml_quote "$body")"$'\n'
}

gemini_command_rel_path() {
  printf '%s.toml' "$1"
}

write_codex_skill() {
  local skill_name="$1"
  local display_name="$2"
  local description="$3"
  local skill_md="$4"
  local extra_yaml="${5:-}"

  write_file "$HOME/.codex/skills/$skill_name/SKILL.md" "$skill_md"
  write_file "$HOME/.codex/skills/$skill_name/agents/openai.yaml" "interface:
  display_name: $(yaml_quote "$display_name")
  short_description: $(yaml_quote "$description")
${extra_yaml}"
}

command_display_name() {
  case "$1" in
    ks | ks.system) printf '%s' "KS System" ;;
    ks.notes) printf '%s' "KS Notes" ;;
    ks.projects) printf '%s' "KS Projects" ;;
    ks.dev) printf '%s' "KS Development" ;;
    ks.ea) printf '%s' "KS Executive Assistant" ;;
    *) return 1 ;;
  esac
}

command_argument_hint() {
  case "$1" in
    ks | ks.system | ks.notes | ks.projects | ks.ea) printf '%s' "<request>" ;;
    ks.dev) printf '%s' "<goal>" ;;
    *) return 1 ;;
  esac
}

command_template_name() {
  case "$1" in
    ks | ks.system) printf '%s' "ks.template.md" ;;
    ks.notes) printf '%s' "ks-notes.template.md" ;;
    ks.projects) printf '%s' "ks-projects.template.md" ;;
    ks.dev) printf '%s' "ks-dev.template.md" ;;
    ks.ea) printf '%s' "ks-executive-assistant.template.md" ;;
    *) return 1 ;;
  esac
}

command_description() {
  case "$1" in
    ks | ks.system) printf '%s' "Keystone system — may start keystone_system/issue or keystone_system/doctor" ;;
    ks.notes) printf '%s' "Notes workflows — may start notes/process_inbox, notes/doctor, notes/init, or notes/setup" ;;
    ks.projects) printf '%s' "Project workflows — may start project/onboard, project/press_release, project/milestone, project/milestone_engineering_handoff, or project/success" ;;
    ks.dev) printf '%s' "Keystone development — may start keystone_system/develop, keystone_system/issue, keystone_system/convention, or keystone_system/doctor" ;;
    ks.ea) printf '%s' "Executive assistant — calendar, inbox, events, portfolio reviews, and task coordination" ;;
    *) return 1 ;;
  esac
}

normalize_command_id() {
  case "$1" in
    ks) printf '%s' "ks.system" ;;
    *) printf '%s' "$1" ;;
  esac
}

render_agent_markdown() {
  local name="$1"
  local description="$2"
  local body="$3"

  cat <<EOF
---
name: $(yaml_quote "$name")
description: $(yaml_quote "$description")
---

$body
EOF
}

render_opencode_agent_markdown() {
  local description="$1"
  local body="$2"

  cat <<EOF
---
description: $(yaml_quote "$description")
mode: subagent
---

$body
EOF
}

render_codex_agent_toml() {
  local name="$1"
  local description="$2"
  local body="$3"

  cat <<EOF
name = $(yaml_quote "$name")
description = $(yaml_quote "$description")
developer_instructions = $(yaml_quote "$body")
EOF
}

render_agent_prompt() {
  local heading="$1"
  local archetype_name="$2"
  local archetype_description="$3"
  local context_block="$4"
  local prompt_tmp
  local convention_name
  local ref_convention

  prompt_tmp="$(mktemp)"
  {
    cat <<EOF
# $heading

Archetype: **$archetype_name**
$archetype_description

---

## Agent context

$context_block
EOF
  } > "$prompt_tmp"

  while IFS= read -r convention_name; do
    [[ -z "$convention_name" ]] && continue
    append_file_content "$prompt_tmp" "$conventions_dir/${convention_name}.md"
  done < <(yq -r ".archetypes.\"$archetype_name\".inlined_conventions[]?" "$archetypes_file")

  mapfile -t ref_conventions < <(yq -r ".archetypes.\"$archetype_name\".referenced_conventions[]?" "$archetypes_file")
  if [[ ${#ref_conventions[@]} -gt 0 ]]; then
    {
      printf '\n---\n\n## Reference Conventions\n\nThe following conventions are available for on-demand context:\n\n'
      for ref_convention in "${ref_conventions[@]}"; do
        printf -- '- [%s](%s/%s.md)\n' "$ref_convention" "$conventions_dir" "$ref_convention"
      done
    } >> "$prompt_tmp"
  fi

  cat "$prompt_tmp"
  rm -f "$prompt_tmp"
}

write_native_agent_definitions() {
  local agent_name agent_json agent_archetype agent_notes_path agent_host
  local agent_archetype_desc context_block prompt description
  local archetype_name archetype_desc archetype_id

  mkdir -p "$HOME/.claude/agents" "$HOME/.gemini/agents" "$HOME/.codex/agents" "$HOME/.config/opencode/agents"

  while IFS= read -r agent_name; do
    [[ -z "$agent_name" ]] && continue
    agent_json="$(json_get ".agents.\"$agent_name\"")"
    agent_archetype="$(printf '%s' "$agent_json" | jq -r '.archetype')"
    agent_notes_path="$(printf '%s' "$agent_json" | jq -r '.notesPath')"
    agent_host="$(printf '%s' "$agent_json" | jq -r '.host')"
    agent_archetype_desc="$(yq -r ".archetypes.\"$agent_archetype\".description // \"\"" "$archetypes_file")"
    description="Keystone OS agent identity for $agent_name. Use when you want this agent's host, notes path, and archetype context."
    context_block="$(cat <<EOF
- Identity kind: os-agent
- Identity: $agent_name
- Host: $agent_host
- Notes path: $agent_notes_path
- Development mode: $development_mode_display
- You are the concrete Keystone OS agent identity \`$agent_name\`.
- Use \`$agent_notes_path\` as the durable notebook root when a workflow asks for notebook context.
EOF
)"
    prompt="$(render_agent_prompt "Keystone OS Agent: $agent_name" "$agent_archetype" "$agent_archetype_desc" "$context_block")"

    write_file "$HOME/.claude/agents/${agent_name}.md" "$(render_agent_markdown "$agent_name" "$description" "$prompt")"
    write_file "$HOME/.gemini/agents/${agent_name}.md" "$(render_agent_markdown "$agent_name" "$description" "$prompt")"
    write_file "$HOME/.config/opencode/agents/${agent_name}.md" "$(render_opencode_agent_markdown "$description" "$prompt")"
    write_file "$HOME/.codex/agents/${agent_name}.toml" "$(render_codex_agent_toml "$agent_name" "$description" "$prompt")"
  done < <(json_get_lines '.agents | keys' 2>/dev/null || true)

  while IFS= read -r archetype_name; do
    [[ -z "$archetype_name" ]] && continue
    archetype_desc="$(yq -r ".archetypes.\"$archetype_name\".description // \"\"" "$archetypes_file")"
    archetype_id="$archetype_name"
    if jq -e --arg name "$archetype_name" '.agents[$name]?' "$manifest_path" >/dev/null; then
      archetype_id="archetype-$archetype_name"
    fi
    description="Keystone archetype agent for $archetype_name. Use when you want this role without impersonating a specific OS agent."
    context_block="$(cat <<EOF
- Identity kind: archetype
- Archetype: $archetype_name
- Development mode: $development_mode_display
- You are a reusable Keystone archetype agent, not a concrete OS-agent identity.
- Do not claim another agent's notebook, host, or personal history unless the user provides that context explicitly.
EOF
)"
    prompt="$(render_agent_prompt "Keystone Archetype Agent: $archetype_name" "$archetype_name" "$archetype_desc" "$context_block")"

    write_file "$HOME/.claude/agents/${archetype_id}.md" "$(render_agent_markdown "$archetype_id" "$description" "$prompt")"
    write_file "$HOME/.gemini/agents/${archetype_id}.md" "$(render_agent_markdown "$archetype_id" "$description" "$prompt")"
    write_file "$HOME/.config/opencode/agents/${archetype_id}.md" "$(render_opencode_agent_markdown "$description" "$prompt")"
    write_file "$HOME/.codex/agents/${archetype_id}.toml" "$(render_codex_agent_toml "$archetype_id" "$description" "$prompt")"
  done < <(yq -r '.archetypes | keys | .[]' "$archetypes_file")
}

ks_allowed_routes_lines=(
  "- Explicit \`\$ks.system doctor\`: start \`keystone_system/doctor\`."
  "- Explicit \`\$ks.system issue\`: start \`keystone_system/issue\`."
  "- Keystone usage help, module discovery, configuration guidance, and workflow recommendations: answer directly when no workflow is needed."
  "- Feature requests, bug reports, paper cuts, and missing Keystone capabilities: start \`keystone_system/issue\`."
  "- Keystone health checks and troubleshooting: start \`keystone_system/doctor\` when the user wants diagnosis rather than documentation."
)

resolved_capabilities=()
while IFS= read -r capability; do
  resolved_capabilities+=("$capability")
done < <(json_get_lines '.resolvedCapabilities')

published_commands=()
while IFS= read -r command_id; do
  published_commands+=("$(normalize_command_id "$command_id")")
done < <(json_get_lines '.publishedCommands')

repos=()
while IFS= read -r repo_name; do
  repos+=("$repo_name")
done < <(json_get_lines '.repos')

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'notes'; then
  ks_allowed_routes_lines+=("- Notes workflows (repair, inbox, init, setup): direct the user to \`/ks.notes\` instead of starting a notes workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'project'; then
  ks_allowed_routes_lines+=("- Project workflows (onboard, press release, milestone, engineering handoff, success): direct the user to \`/ks.projects\` instead of starting a project workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'executive-assistant'; then
  ks_allowed_routes_lines+=("- Executive assistant workflows (calendar, inbox, events, portfolio reviews, task coordination): direct the user to \`/ks.ea\` instead of starting executive_assistant workflows directly.")
fi

repo_checkout="$(json_get '.repoCheckout')"
fallback_conventions_dir="$(json_get '.fallbackConventionsDir')"
fallback_templates_dir="$(json_get '.fallbackTemplatesDir')"
archetype="$(json_get '.archetype')"
development_mode="$(json_get '.developmentMode')"

use_live_checkout=false
if [[ "$repo_checkout" != "null" && -n "$repo_checkout" && -d "$repo_checkout" ]]; then
  use_live_checkout=true
fi

if [[ "$use_live_checkout" == "true" ]]; then
  conventions_dir="$repo_checkout/conventions"
  templates_dir="$repo_checkout/modules/terminal/agent-assets"
else
  if [[ "$development_mode" == "true" ]]; then
    echo "Warning: live keystone repo checkout not found at $repo_checkout; falling back to immutable assets" >&2
  fi

  if [[ "$fallback_conventions_dir" == "null" || -z "$fallback_conventions_dir" || ! -d "$fallback_conventions_dir" ]]; then
    echo "Error: fallback conventions directory not found at $fallback_conventions_dir" >&2
    exit 1
  fi

  if [[ "$fallback_templates_dir" == "null" || -z "$fallback_templates_dir" || ! -d "$fallback_templates_dir" ]]; then
    echo "Error: fallback templates directory not found at $fallback_templates_dir" >&2
    exit 1
  fi

  conventions_dir="$fallback_conventions_dir"
  templates_dir="$fallback_templates_dir"
fi

archetypes_file="$conventions_dir/archetypes.yaml"

if [[ ! -f "$archetypes_file" ]]; then
  echo "Error: archetypes.yaml not found at $archetypes_file" >&2
  exit 1
fi

capabilities_display="_none_"
if [[ ${#resolved_capabilities[@]} -gt 0 ]]; then
  capabilities_display="$(printf '%s, ' "${resolved_capabilities[@]}")"
  capabilities_display="${capabilities_display%, }"
fi

published_commands_display="_none_"
if [[ ${#published_commands[@]} -gt 0 ]]; then
  published_commands_display="$(printf '%s, ' "${published_commands[@]}")"
  published_commands_display="${published_commands_display%, }"
fi

development_mode_display="disabled"
if [[ "$development_mode" == "true" ]]; then
  development_mode_display="enabled"
fi

ks_allowed_routes="$(printf '%s\n' "${ks_allowed_routes_lines[@]}")"
archetype_description="$(yq -r ".archetypes.\"$archetype\".description // \"\"" "$archetypes_file")"

global_agents_tmp="$(mktemp)"
{
  cat <<EOF
# Keystone Conventions

Archetype: **$archetype**
$archetype_description

---

## Keystone session

- Canonical instruction path: \`~/.keystone/AGENTS.md\`
- Development mode: $development_mode_display
- Available Keystone capabilities: $capabilities_display
- Published Keystone commands: $published_commands_display
EOF
} > "$global_agents_tmp"

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'notes'; then
  cat <<'EOF' >> "$global_agents_tmp"

---

## Notes command guidance

- Route durable note capture, note cleanup, inbox promotion, and notebook repair requests through `ks.notes`.
- Use `ks.notes` proactively when a task produces durable decisions, meaningful findings, or reusable operational context.
- On Keystone systems, use `NOTES_DIR` as the canonical notebook root. It resolves to `keystone.notes.path` (`~/notes` for human users, per-agent notes paths for OS agents).
- When note structure, tags, frontmatter, shared-surface refs, or zk workflow details matter, read `~/.config/keystone/conventions/process.notes.md` and `~/.config/keystone/conventions/tool.zk-notes.md`.
- When a task is tied to an issue, pull request, or milestone, capture normalized refs in notes when known and keep the shared surface as the public system of record.
EOF
fi

cat <<'EOF' >> "$global_agents_tmp"

---

## Shared-surface tracking

- For issue-backed work, follow `process.issue-journal` and post `Work Started` and `Work Update` comments on the source issue.
- For milestone and board-backed work, follow `process.project-board` so issue and PR state stays visible on the shared board.
- Treat issues, pull requests, milestones, and boards as the canonical public record for status, review state, and decisions that affect collaborators.
- Use notes to preserve durable rationale and memory, not to replace shared-surface tracking.
EOF

while IFS= read -r convention_name; do
  [[ -z "$convention_name" ]] && continue
  append_file_content "$global_agents_tmp" "$conventions_dir/${convention_name}.md"
done < <(yq -r ".archetypes.\"$archetype\".inlined_conventions[]?" "$archetypes_file")

mapfile -t referenced_global_conventions < <(yq -r ".archetypes.\"$archetype\".referenced_conventions[]?" "$archetypes_file")
if [[ ${#referenced_global_conventions[@]} -gt 0 ]]; then
  {
    printf '\n---\n\n## Reference Conventions\n\nThe following conventions are available for on-demand context:\n\n'
    for convention_name in "${referenced_global_conventions[@]}"; do
      printf -- '- [%s](%s/%s.md)\n' "$convention_name" "$conventions_dir" "$convention_name"
    done
  } >> "$global_agents_tmp"
fi

global_agents_content="$(cat "$global_agents_tmp")"
rm -f "$global_agents_tmp"

write_file "$HOME/.keystone/AGENTS.md" "$global_agents_content"
write_file "$HOME/.claude/CLAUDE.md" "$global_agents_content"
write_file "$HOME/.gemini/GEMINI.md" "$global_agents_content"
write_file "$HOME/.codex/AGENTS.md" "$global_agents_content"
write_file "$HOME/.config/opencode/AGENTS.md" "$global_agents_content"

repos_agents_tmp="$(mktemp)"
{
  cat <<'EOF'
# Keystone repos

This directory (`~/.keystone/repos/`) is the agent-space root for the keystone
system. It contains the core repositories that define and operate this machine's
infrastructure. See `process.keystone-development` (inlined below) for the
development workflow, tooling, and how changes flow through the system.

## Repositories

EOF
  for repo_name in "${repos[@]}"; do
    if [[ "$repo_name" == */notes ]]; then
      continue
    fi
    printf '### `%s` → [`%s/AGENTS.md`](%s/AGENTS.md)\n\n' "$repo_name" "$repo_name" "$repo_name"
  done
} > "$repos_agents_tmp"

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'notes'; then
  cat <<'EOF' >> "$repos_agents_tmp"

## Notes command guidance

- Route durable note capture, note cleanup, inbox promotion, and notebook repair requests through `ks.notes`.
- Use `ks.notes` proactively when a task produces durable decisions, meaningful findings, or reusable operational context.
- On Keystone systems, the human notebook lives at `NOTES_DIR` (`~/notes` by default), not in the `~/.keystone/repos/` inventory.
- When note structure, tags, frontmatter, shared-surface refs, or zk workflow details matter, read `~/.config/keystone/conventions/process.notes.md` and `~/.config/keystone/conventions/tool.zk-notes.md`.
- When a task is tied to an issue, pull request, or milestone, capture normalized refs in notes when known and keep the shared surface as the public system of record.
EOF
fi

cat <<'EOF' >> "$repos_agents_tmp"

## Shared-surface tracking

- For issue-backed work, follow `process.issue-journal` and post `Work Started` and `Work Update` comments on the source issue.
- For milestone and board-backed work, follow `process.project-board` so issue and PR state stays visible on the shared board.
- Treat issues, pull requests, milestones, and boards as the canonical public record for status, review state, and decisions that affect collaborators.
- Use notes to preserve durable rationale and memory, not to replace shared-surface tracking.
EOF

while IFS= read -r convention_name; do
  [[ -z "$convention_name" ]] && continue
  append_file_content "$repos_agents_tmp" "$conventions_dir/${convention_name}.md"
done < <(yq -r '.archetypes."keystone-developer".inlined_conventions[]?' "$archetypes_file")

mapfile -t referenced_repo_conventions < <(yq -r '.archetypes."keystone-developer".referenced_conventions[]?' "$archetypes_file")
if [[ ${#referenced_repo_conventions[@]} -gt 0 ]]; then
  {
    printf '\n---\n\n## Reference Conventions\n\nThe following conventions are available for on-demand context:\n\n'
    for convention_name in "${referenced_repo_conventions[@]}"; do
      printf -- '- [%s](ncrmro/keystone/conventions/%s.md)\n' "$convention_name" "$convention_name"
    done
  } >> "$repos_agents_tmp"
fi

repos_agents_content="$(cat "$repos_agents_tmp")"
rm -f "$repos_agents_tmp"

write_file "$HOME/.keystone/repos/AGENTS.md" "$repos_agents_content"

managed_claude_commands=(ks.md ks.system.md ks.notes.md ks.projects.md ks.dev.md ks.ea.md)
for command_file in "${managed_claude_commands[@]}"; do
  rm -f "$HOME/.claude/commands/$command_file"
done

managed_gemini_commands=(ks.toml ks.system.toml ks.notes.toml ks.projects.toml ks.dev.toml ks.ea.toml deepwork.toml wrap-up.toml)
for command_file in "${managed_gemini_commands[@]}"; do
  rm -f "$HOME/.gemini/commands/$command_file"
done

managed_opencode_commands=(ks.md ks.system.md ks.notes.md ks.projects.md ks.dev.md ks.ea.md)
for command_file in "${managed_opencode_commands[@]}"; do
  rm -f "$HOME/.config/opencode/commands/$command_file"
done

rm -rf "$HOME/.claude/skills/ks" "$HOME/.config/opencode/skills/ks"

for command_id in "${published_commands[@]}"; do
  description="$(command_description "$command_id")"
  argument_hint="$(command_argument_hint "$command_id")"
  display_name="$(command_display_name "$command_id")"
  template_name="$(command_template_name "$command_id")"
  command_body="$(render_template "$templates_dir/$template_name")"
  skill_name="$(printf '%s' "$command_id" | tr '.' '-')"

  claude_content="$(render_frontmatter "$command_id" "$description" "$argument_hint" "$display_name")"$'\n\n'"$command_body"$'\n'
  write_file "$HOME/.claude/commands/${command_id}.md" "$claude_content"

  gemini_rel="$(gemini_command_rel_path "$command_id")"
  write_gemini_command "$gemini_rel" "$description" "$command_body"

  write_file "$HOME/.config/opencode/commands/${command_id}.md" "$command_body"$'\n'

  ks_skill_md="$(render_skill_md "$skill_name" "$description" "$command_body")"
  write_file "$HOME/.claude/skills/${skill_name}/SKILL.md" "$ks_skill_md"
  write_file "$HOME/.config/opencode/skills/${skill_name}/SKILL.md" "$ks_skill_md"

  if [[ "$command_id" == "ks.ea" ]]; then
    ea_conventions=(
      "roles/executive-assistant.md:executive-assistant.md"
      "tool.calendula.md:tool.calendula.md"
      "tool.himalaya.md:tool.himalaya.md"
      "tool.stalwart.md:tool.stalwart.md"
    )
    for entry in "${ea_conventions[@]}"; do
      src_rel="${entry%%:*}"
      dest_name="${entry##*:}"
      src_file="$conventions_dir/$src_rel"
      if [[ -f "$src_file" ]]; then
        content="$(cat "$src_file")"
        write_file "$HOME/.claude/skills/${skill_name}/${dest_name}" "$content"
        write_file "$HOME/.config/opencode/skills/${skill_name}/${dest_name}" "$content"
      fi
    done
  fi
done

deepwork_body="$(cat "$templates_dir/deepwork-skill.template.md")"
deepwork_skill_md="$(render_skill_md "deepwork" "Start or continue DeepWork workflows using MCP tools" "$deepwork_body")"
write_file "$HOME/.claude/skills/deepwork/SKILL.md" "$deepwork_skill_md"
write_file "$HOME/.config/opencode/skills/deepwork/SKILL.md" "$deepwork_skill_md"
write_gemini_command "deepwork.toml" "Start or continue DeepWork workflows using MCP tools" "$deepwork_body"
write_codex_skill "deepwork" "DeepWork" "Start or continue DeepWork workflows using MCP tools" "$deepwork_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

wrapup_body="$(cat "$templates_dir/wrap-up-skill.template.md")"
wrapup_skill_md="$(render_skill_md "wrap-up" "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human" "$wrapup_body")"
write_file "$HOME/.claude/skills/wrap-up/SKILL.md" "$wrapup_skill_md"
write_file "$HOME/.config/opencode/skills/wrap-up/SKILL.md" "$wrapup_skill_md"
write_gemini_command "wrap-up.toml" "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human" "$wrapup_body"
write_codex_skill "wrap-up" "Wrap-up" "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human" "$wrapup_skill_md"

legacy_codex_skill_names=(
  agent-bootstrap agent-doctor agent-issue agent-onboard daily_status-send
  deepwork-review engineer ks-convention ks-develop ks-doctor ks-issue
  ks-update marketing-social_media_setup milestone-eng_handoff milestone-setup
  notes-doctor notes-process_inbox notes-project notes-report portfolio-review
  project-onboard project-press_release project-success repo-doctor repo-setup
  research-deep research-quick task-ingest task-run ks
)
for skill_name in "${legacy_codex_skill_names[@]}"; do
  rm -rf "$HOME/.codex/skills/$skill_name"
done

for command_id in "${published_commands[@]}"; do
  description="$(command_description "$command_id")"
  display_name="$(command_display_name "$command_id")"
  template_name="$(command_template_name "$command_id")"
  command_body="$(render_template "$templates_dir/$template_name")"
  skill_name="$(codex_skill_name "$command_id")"
  skill_body="$(render_codex_skill_body "$command_body" "$skill_name")"
  skill_md="$(render_skill_md "$skill_name" "$description" "$skill_body")"

  write_codex_skill "$skill_name" "$display_name" "$description" "$skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

  if [[ "$command_id" == "ks.ea" ]]; then
    ea_conventions=(
      "roles/executive-assistant.md:executive-assistant.md"
      "tool.calendula.md:tool.calendula.md"
      "tool.himalaya.md:tool.himalaya.md"
      "tool.stalwart.md:tool.stalwart.md"
    )
    for entry in "${ea_conventions[@]}"; do
      src_rel="${entry%%:*}"
      dest_name="${entry##*:}"
      src_file="$conventions_dir/$src_rel"
      if [[ -f "$src_file" ]]; then
        content="$(cat "$src_file")"
        write_file "$HOME/.codex/skills/${skill_name}/${dest_name}" "$content"
      fi
    done
  fi
done

write_native_agent_definitions
