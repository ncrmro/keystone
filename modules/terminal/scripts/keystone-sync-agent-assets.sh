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
files, curated commands, and Codex skills.
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

  printf '\n' >> "$output_file"
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

codex_skill_name() {
  printf '%s' "$1" | tr '.' '-'
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

write_shared_skill() {
  local skill_name="$1"
  local skill_md="$2"
  write_file "$HOME/.claude/skills/$skill_name/SKILL.md" "$skill_md"
  write_file "$HOME/.gemini/skills/$skill_name/SKILL.md" "$skill_md"
  write_file "$HOME/.config/opencode/skills/$skill_name/SKILL.md" "$skill_md"
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

command_display_name() {
  case "$1" in
    ks.system) printf '%s' "KS System" ;;
    ks.assistant) printf '%s' "KS Assistant" ;;
    ks.notes) printf '%s' "KS Notes" ;;
    ks.projects) printf '%s' "KS Projects" ;;
    ks.dev) printf '%s' "KS Development" ;;
    ks.ea) printf '%s' "KS Executive Assistant" ;;
    ks.engineer) printf '%s' "KS Engineer" ;;
    ks.product) printf '%s' "KS Product" ;;
    ks.project-manager) printf '%s' "KS Project Manager" ;;
    *) return 1 ;;
  esac
}

command_argument_hint() {
  case "$1" in
    ks.system|ks.assistant|ks.notes|ks.projects|ks.ea|ks.product|ks.project-manager) printf '%s' "<request>" ;;
    ks.dev|ks.engineer) printf '%s' "<goal>" ;;
    *) return 1 ;;
  esac
}

command_template_name() {
  local skill_key
  skill_key="$(command_skill_key "$1")"
  if [[ -n "$skill_key" ]]; then
    yq -r ".skills.\"$skill_key\".template" "$archetypes_file"
    return
  fi
  case "$1" in
    ks.system) printf '%s' "ks.template.md" ;;
    ks.assistant) printf '%s' "ks-assistant.template.md" ;;
    ks.notes) printf '%s' "ks-notes.template.md" ;;
    ks.projects) printf '%s' "ks-projects.template.md" ;;
    ks.dev) printf '%s' "ks-dev.template.md" ;;
    *) return 1 ;;
  esac
}

command_description() {
  local skill_key
  skill_key="$(command_skill_key "$1")"
  if [[ -n "$skill_key" ]]; then
    yq -r ".skills.\"$skill_key\".description" "$archetypes_file"
    return
  fi
  case "$1" in
    ks.system)
      local desc="Keystone system — may start keystone_system/issue or keystone_system/doctor"
      if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'executive-assistant'; then
        desc+=", or executive_assistant workflows"
      fi
      printf '%s' "$desc"
      ;;
    ks.assistant) printf '%s' "Personal assistant — may start personal_assistant/reservation, personal_assistant/birthday, personal_assistant/calendar_prioritize, or personal_assistant/memory_search" ;;
    ks.notes) printf '%s' "Notes workflows — may start notes/process_inbox, notes/doctor, notes/init, or notes/setup" ;;
    ks.projects) printf '%s' "Project workflows — may start project/onboard, project/press_release, or project/success" ;;
    ks.dev) printf '%s' "Keystone development — may start keystone_system/develop, keystone_system/issue, keystone_system/convention, or keystone_system/doctor" ;;
    *) return 1 ;;
  esac
}

# Map command ID to archetypes.yaml skill key (empty string if not a skill command)
command_skill_key() {
  case "$1" in
    ks.engineer) printf '%s' "engineer" ;;
    ks.product) printf '%s' "product" ;;
    ks.project-manager) printf '%s' "project-manager" ;;
    ks.ea) printf '%s' "executive-assistant" ;;
    *) printf '' ;;
  esac
}

# Copy colocated conventions and roles into a skill directory
colocate_skill_conventions() {
  local skill_key="$1"
  local target_dir="$2"
  local conv_name src_file

  while IFS= read -r conv_name; do
    [[ -z "$conv_name" ]] && continue
    src_file="$conventions_dir/${conv_name}.md"
    [[ -f "$src_file" ]] && write_file "${target_dir}/${conv_name}.md" "$(cat "$src_file")"
  done < <(yq -r ".skills.\"$skill_key\".colocated_conventions[]?" "$archetypes_file")

  while IFS= read -r conv_name; do
    [[ -z "$conv_name" ]] && continue
    src_file="$conventions_dir/roles/${conv_name}.md"
    [[ -f "$src_file" ]] && write_file "${target_dir}/${conv_name}.md" "$(cat "$src_file")"
  done < <(yq -r ".skills.\"$skill_key\".colocated_roles[]?" "$archetypes_file")
}

ks_allowed_routes_lines=(
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
  published_commands+=("$command_id")
done < <(json_get_lines '.publishedCommands')

repos=()
while IFS= read -r repo_name; do
  repos+=("$repo_name")
done < <(json_get_lines '.repos')

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'assistant'; then
  ks_allowed_routes_lines+=("- Personal assistant requests (reservations, birthdays, calendar, photo memories): direct the user to \`/ks.assistant\` instead of handling directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'notes'; then
  ks_allowed_routes_lines+=("- Notes workflows (repair, inbox, init, setup): direct the user to \`/ks.notes\` instead of starting a notes workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'project'; then
  ks_allowed_routes_lines+=("- Project workflows (onboard, press release, success): direct the user to \`/ks.projects\` instead of starting a project workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'executive-assistant'; then
  ks_allowed_routes_lines+=("- Executive assistant workflows (calendar, inbox, events, portfolio reviews, task coordination): direct the user to \`/ks.ea\` instead of starting executive_assistant workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'engineer'; then
  ks_allowed_routes_lines+=("- Engineering workflows (implementation, code review, architecture, CI): direct the user to \`/ks.engineer\` instead of starting engineer workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'product'; then
  ks_allowed_routes_lines+=("- Product workflows (press releases, milestones, stakeholder communication): direct the user to \`/ks.product\` instead of starting project workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'project-manager'; then
  ks_allowed_routes_lines+=("- Project management workflows (task decomposition, tracking, boards): direct the user to \`/ks.pm\` instead of managing tasks directly.")
fi

repo_checkout="$(json_get '.repoCheckout')"
archetype="$(json_get '.archetype')"
development_mode="$(json_get '.developmentMode')"

# Resolve templates_dir.
# Priority: KEYSTONE_AGENT_TEMPLATES_DIR (Nix-store bundled) → live checkout → error.
if [[ -n "${KEYSTONE_AGENT_TEMPLATES_DIR:-}" && -d "$KEYSTONE_AGENT_TEMPLATES_DIR" ]]; then
  templates_dir="$KEYSTONE_AGENT_TEMPLATES_DIR"
elif [[ "$repo_checkout" != "null" && -n "$repo_checkout" && -d "$repo_checkout/modules/terminal/agent-assets" ]]; then
  templates_dir="$repo_checkout/modules/terminal/agent-assets"
else
  echo "Error: no templates directory found." >&2
  if [[ -n "${KEYSTONE_AGENT_TEMPLATES_DIR:-}" ]]; then
    echo "  KEYSTONE_AGENT_TEMPLATES_DIR=$KEYSTONE_AGENT_TEMPLATES_DIR (not found)" >&2
  else
    echo "  KEYSTONE_AGENT_TEMPLATES_DIR is not set" >&2
  fi
  if [[ "$repo_checkout" != "null" && -n "$repo_checkout" ]]; then
    echo "  $repo_checkout/modules/terminal/agent-assets (not found)" >&2
  else
    echo "  repoCheckout not set in manifest" >&2
  fi
  exit 1
fi

# Resolve conventions_dir from live checkout or manifest fallback.
if [[ "$repo_checkout" != "null" && -n "$repo_checkout" ]]; then
  if [[ ! -d "$repo_checkout" ]]; then
    repo_slug="${repo_checkout##*/.keystone/repos/}"
    echo "Live keystone repo checkout not found at $repo_checkout — cloning $repo_slug..."
    mkdir -p "$(dirname "$repo_checkout")"
    git clone "https://github.com/$repo_slug.git" "$repo_checkout"
  fi
  conventions_dir="$repo_checkout/conventions"
else
  conventions_dir="$(json_get '.fallbackConventionsDir')"
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

global_agents_tmp="$(mktemp)"
cat <<'EOF' > "$global_agents_tmp"
# Shared-surface tracking

- For issue-backed work, post `Work Started` and `Work Update` comments on the source issue.
- Treat issues, pull requests, milestones, and boards as the canonical public record.

# Commit format

- Use Conventional Commits: `type(scope): subject`.
- Valid types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `build`.
- Each commit SHOULD represent one logical change.
EOF

while IFS= read -r convention_name; do
  append_file_content "$global_agents_tmp" "$conventions_dir/${convention_name}.md"
done < <(yq -r ".archetypes.\"$archetype\".inlined_conventions[]?" "$archetypes_file")

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
  append_file_content "$repos_agents_tmp" "$conventions_dir/${convention_name}.md"
done < <(yq -r '.archetypes."keystone-developer".inlined_conventions[]?' "$archetypes_file")

repos_agents_content="$(cat "$repos_agents_tmp")"
rm -f "$repos_agents_tmp"

write_file "$HOME/.keystone/repos/AGENTS.md" "$repos_agents_content"

# Clean up legacy command files (skills are the canonical format now)
for command_file in ks.md ks.system.md ks.assistant.md ks.notes.md ks.projects.md ks.dev.md ks.ea.md ks.engineer.md ks.product.md ks.project-manager.md ks.pm.md; do
  rm -f "$HOME/.claude/commands/$command_file"
  rm -f "$HOME/.config/opencode/commands/$command_file"
done
for command_file in ks.toml notes.toml projects.toml dev.toml deepwork.toml ks.ea.toml ks.engineer.toml ks.product.toml ks.pm.toml wrap-up.toml; do
  rm -f "$HOME/.gemini/commands/$command_file"
done
rm -rf "$HOME/.claude/skills/ks"
rm -rf "$HOME/.claude/skills/ks-pm"
rm -rf "$HOME/.claude/skills/ks-assistant"
rm -rf "$HOME/.config/opencode/skills/ks"
rm -rf "$HOME/.config/opencode/skills/ks-pm"
rm -rf "$HOME/.config/opencode/skills/ks-assistant"

for command_id in "${published_commands[@]}"; do
  description="$(command_description "$command_id")"
  display_name="$(command_display_name "$command_id")"
  template_name="$(command_template_name "$command_id")"
  command_body="$(render_template "$templates_dir/$template_name")"
  skill_name="$command_id"
  legacy_skill_name="$(printf '%s' "$command_id" | tr '.' '-')"

  # Clean up legacy dash-named skill directories
  if [[ "$skill_name" != "$legacy_skill_name" ]]; then
    rm -rf "$HOME/.claude/skills/${legacy_skill_name}"
    rm -rf "$HOME/.gemini/skills/${legacy_skill_name}"
    rm -rf "$HOME/.config/opencode/skills/${legacy_skill_name}"
  fi

  # Skills are the canonical format — all CLIs with skill support get them
  ks_skill_md="$(render_skill_md "$skill_name" "$description" "$command_body")"
  write_file "$HOME/.claude/skills/${skill_name}/SKILL.md" "$ks_skill_md"
  write_file "$HOME/.gemini/skills/${skill_name}/SKILL.md" "$ks_skill_md"
  write_file "$HOME/.config/opencode/skills/${skill_name}/SKILL.md" "$ks_skill_md"

  # Colocate conventions for skill commands
  skill_key="$(command_skill_key "$command_id")"
  if [[ -n "$skill_key" ]]; then
    colocate_skill_conventions "$skill_key" "$HOME/.claude/skills/${skill_name}"
    colocate_skill_conventions "$skill_key" "$HOME/.gemini/skills/${skill_name}"
    colocate_skill_conventions "$skill_key" "$HOME/.config/opencode/skills/${skill_name}"
  fi
done

deepwork_body="$(cat "$templates_dir/deepwork-skill.template.md")"
deepwork_skill_md="$(render_skill_md "deepwork" "Start or continue DeepWork workflows using MCP tools" "$deepwork_body")"
write_shared_skill "deepwork" "$deepwork_skill_md"

write_codex_skill "deepwork" "DeepWork" "Start or continue DeepWork workflows using MCP tools" "$deepwork_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

deepplan_body="$(cat <<'EOF'
# DeepPlan

Structured planning workflow that explores the codebase, generates competing
designs, and produces an executable DeepWork job definition.

## How to Use

1. Call `EnterPlanMode` if not already in plan mode
2. Call `start_workflow` with:
   - `job_name`: `"deepplan"`
   - `workflow_name`: `"create_deep_plan"`
   - `goal`: the user's planning request
3. Follow the step instructions returned by the MCP tools — they supersede
   the default planning phases

## Intent Parsing

When the user invokes `/deepplan`, parse their intent:
- **With goal**: `/deepplan <goal>` → enter plan mode and start the workflow
  with `<goal>`
- **No context**: `/deepplan` alone → enter plan mode and start the workflow
  using conversation context as the goal; if no context, ask the user what
  they want to plan
EOF
)"
deepplan_skill_md="$(render_skill_md "deepplan" "Start structured planning — explores, designs, and produces an executable plan" "$deepplan_body")"
write_shared_skill "deepplan" "$deepplan_skill_md"

write_codex_skill "deepplan" "DeepPlan" "Start structured planning — explores, designs, and produces an executable plan" "$deepplan_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

deepreviews_body="$(cat "$templates_dir/deepreviews-skill.template.md")"
deepreviews_skill_md="$(render_skill_md "deepreviews" "Reference documentation for DeepWork Reviews — automated code review rules using .deepreview configs and DeepSchema-generated rules" "$deepreviews_body")"
write_shared_skill "deepreviews" "$deepreviews_skill_md"

write_codex_skill "deepreviews" "DeepWork Reviews" "Reference documentation for DeepWork Reviews" "$deepreviews_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

deepschema_body="$(cat "$templates_dir/deepschema-skill.template.md")"
deepschema_skill_md="$(render_skill_md "deepschema" "Create and manage DeepSchemas — rich file-level schemas with automatic validation and review generation" "$deepschema_body")"
write_shared_skill "deepschema" "$deepschema_skill_md"

write_codex_skill "deepschema" "DeepSchema" "Create and manage DeepSchemas" "$deepschema_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

review_body="$(cat "$templates_dir/review-skill.template.md")"
review_skill_md="$(render_skill_md "review" "Run DeepWork Reviews on the current branch — review changed files using .deepreview rules" "$review_body")"
write_shared_skill "review" "$review_skill_md"

write_codex_skill "review" "Review" "Run DeepWork Reviews on the current branch" "$review_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

configure_reviews_body="$(cat "$templates_dir/configure-reviews-skill.template.md")"
configure_reviews_skill_md="$(render_skill_md "configure_reviews" "Set up DeepWork Reviews — automated code review rules using .deepreview config files" "$configure_reviews_body")"
write_shared_skill "configure_reviews" "$configure_reviews_skill_md"

write_codex_skill "configure_reviews" "Configure Reviews" "Set up DeepWork Reviews" "$configure_reviews_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

wrapup_body="$(cat "$templates_dir/wrap-up-skill.template.md")"
wrapup_skill_md="$(render_skill_md "wrap-up" "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human" "$wrapup_body")"
write_shared_skill "wrap-up" "$wrapup_skill_md"

write_codex_skill "wrap-up" "Wrap-up" "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human" "$wrapup_skill_md"

legacy_codex_skill_names=(
  agent-bootstrap agent-doctor agent-issue agent-onboard daily_status-send
  deepwork-review engineer ks-convention ks-develop ks-doctor ks-issue
  ks-update marketing-social_media_setup milestone-eng_handoff milestone-setup
  notes-doctor notes-process_inbox notes-project notes-report portfolio-review
  project-onboard project-press_release project-success repo-doctor repo-setup
  research-deep research-quick task-ingest task-run
  ks ks-pm
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

  # Colocate conventions for skill commands in Codex
  skill_key="$(command_skill_key "$command_id")"
  if [[ -n "$skill_key" ]]; then
    colocate_skill_conventions "$skill_key" "$HOME/.codex/skills/${skill_name}"
  fi
done
