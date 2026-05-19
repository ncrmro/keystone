#!/usr/bin/env bash
# Sync generated Keystone agent assets from the current profile manifest.
# See conventions/code.shell-scripts.md and
# conventions/tool.cli-coding-agents.md § "Consumer Flake Agent Assets".

set -euo pipefail

manifest_path="${KEYSTONE_AGENT_ASSETS_MANIFEST:-$HOME/.config/keystone/agent-assets.json}"

usage() {
  cat <<'EOF'
Usage: keystone-sync-agent-assets

Refresh generated Keystone agent assets for the current user from the current
profile manifest. Skill content is written into the consumer flake at
<consumer-flake>/agents/<tool>/skills/<name>/ — never directly to $HOME.
Home-manager activation symlinks each ~/.<tool>/<subdir> at the corresponding
consumer-flake path.

The canonical instruction file is written once to
<consumer-flake>/agents/_shared/AGENTS.md and each per-tool instruction
filename (CLAUDE.md, GEMINI.md, codex AGENTS.md) is a symlink pointing at
it. Skill bodies and their colocated conventions/roles are written
canonically to <consumer-flake>/agents/_shared/skills/<key>/ so they're
reviewable as one copy per skill, not three. Consumer flakes commit
_shared/ and gitignore the per-tool dirs (which contain gitignored
rendered copies plus codex's hyphenated-name fan-out).

The merged skill map is built from conventions/archetypes.yaml.skills
(keystone defaults) plus an optional <consumer-flake>/agents/_shared/skills.yaml
(user overrides, wholesale-replace on key conflict).
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

# Resolve the consumer-flake agents root. This is where skill content lands.
# Precedence (matches the Rust precedence in packages/ks/src/app.rs:current_system_flake_path):
#   1. KEYSTONE_CONSUMER_FLAKE env var (test override)
#   2. /run/current-system/keystone-system-flake (runtime pointer file)
#   3. Manifest's eval-time consumerFlakeAgents value (Nix-eval fallback)
# The runtime pointer is a *regular file* written by modules/shared/system-flake.nix
# containing the path as text — not a symlink — so read with `read`, not
# `readlink`. The activation in generated-agent-assets.nix uses the same pattern.
consumer_flake_root="${KEYSTONE_CONSUMER_FLAKE:-}"
if [[ -z "$consumer_flake_root" && -f /run/current-system/keystone-system-flake ]]; then
  IFS= read -r consumer_flake_root < /run/current-system/keystone-system-flake || consumer_flake_root=""
fi
if [[ -z "$consumer_flake_root" ]]; then
  manifest_consumer="$(jq -r '.consumerFlakeAgents // ""' "$manifest_path")"
  if [[ -n "$manifest_consumer" ]]; then
    # The manifest stores `<flake>/agents` already; strip the trailing /agents
    # to get the flake root so the rest of this script can re-append per-tool.
    consumer_flake_root="${manifest_consumer%/agents}"
  fi
fi
if [[ -z "$consumer_flake_root" ]]; then
  echo "Error: cannot determine consumer-flake path. Set KEYSTONE_CONSUMER_FLAKE or ensure /run/current-system/keystone-system-flake is present." >&2
  exit 1
fi

CONSUMER_FLAKE_AGENTS="$consumer_flake_root/agents"
CONSUMER_FLAKE_SHARED="$CONSUMER_FLAKE_AGENTS/_shared"
# Canonical (committed) skill content. Claude and Gemini receive identical
# SKILL.md content, so a single committed body per skill lives here and is
# review-traceable in the consumer flake. Codex needs hyphenated names and a
# skill-invocation footer, so its rendering stays in the gitignored codex dir.
SHARED_SKILLS_DEST="$CONSUMER_FLAKE_SHARED/skills"
CLAUDE_SKILLS_DEST="$CONSUMER_FLAKE_AGENTS/claude/skills"
GEMINI_SKILLS_DEST="$CONSUMER_FLAKE_AGENTS/gemini/skills"
CODEX_SKILLS_DEST="$CONSUMER_FLAKE_AGENTS/codex/skills"
# OpenCode skills stay on the home dir for now — opencode is not yet wired into
# the symlink activation. Future scope: parameterize when opencode joins.
OPENCODE_SKILLS_DEST="$HOME/.config/opencode/skills"
# Optional user-authored override for the skill map. Same flat schema as
# archetypes.yaml.skills. Wholesale-replace merge: user keys win on conflict;
# user-only keys are emitted as new skills. Absent file is fine.
USER_SKILLS_YAML="$CONSUMER_FLAKE_SHARED/skills.yaml"

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
  write_file "$CODEX_SKILLS_DEST/$skill_name/SKILL.md" "$skill_md"
  write_file "$CODEX_SKILLS_DEST/$skill_name/agents/openai.yaml" "interface:
  display_name: $(yaml_quote "$display_name")
  short_description: $(yaml_quote "$description")
${extra_yaml}"
}

write_shared_skill() {
  local skill_name="$1"
  local skill_md="$2"
  write_file "$CLAUDE_SKILLS_DEST/$skill_name/SKILL.md" "$skill_md"
  write_file "$GEMINI_SKILLS_DEST/$skill_name/SKILL.md" "$skill_md"
  write_file "$OPENCODE_SKILLS_DEST/$skill_name/SKILL.md" "$skill_md"
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
    ks-system) printf '%s' "KS System" ;;
    ks-assistant) printf '%s' "KS Assistant" ;;
    ks-notes) printf '%s' "KS Notes" ;;
    ks-projects) printf '%s' "KS Projects" ;;
    ks-dev) printf '%s' "KS Development" ;;
    ks-ea) printf '%s' "KS Executive Assistant" ;;
    ks-engineer) printf '%s' "KS Engineer" ;;
    ks-product) printf '%s' "KS Product" ;;
    ks-project-manager) printf '%s' "KS Project Manager" ;;
    *) return 1 ;;
  esac
}

command_argument_hint() {
  case "$1" in
    ks-system|ks-assistant|ks-notes|ks-projects|ks-ea|ks-product|ks-project-manager) printf '%s' "<request>" ;;
    ks-dev|ks-engineer) printf '%s' "<goal>" ;;
    *) return 1 ;;
  esac
}

command_template_name() {
  local template
  template="$(jq -r --arg k "$1" '.[$k].template // empty' <<< "$merged_skills_json")"
  if [[ -n "$template" ]]; then
    printf '%s' "$template"
    return
  fi
  case "$1" in
    ks-system) printf '%s' "ks.template.md" ;;
    ks-assistant) printf '%s' "ks-assistant.template.md" ;;
    ks-notes) printf '%s' "ks-notes.template.md" ;;
    ks-projects) printf '%s' "ks-projects.template.md" ;;
    ks-dev) printf '%s' "ks-dev.template.md" ;;
    *) return 1 ;;
  esac
}

command_description() {
  local desc
  desc="$(jq -r --arg k "$1" '.[$k].description // empty' <<< "$merged_skills_json")"
  if [[ -n "$desc" ]]; then
    printf '%s' "$desc"
    return
  fi
  case "$1" in
    ks-system)
      desc="Keystone system — may start keystone_system/issue or keystone_system/doctor"
      if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'executive-assistant'; then
        desc+=", or executive_assistant workflows"
      fi
      printf '%s' "$desc"
      ;;
    ks-assistant) printf '%s' "Personal assistant — may start personal_assistant/reservation, personal_assistant/birthday, personal_assistant/calendar_prioritize, or personal_assistant/memory_search" ;;
    ks-notes) printf '%s' "Notes workflows — may start notes/process_inbox, notes/doctor, notes/init, or notes/setup" ;;
    ks-projects) printf '%s' "Project workflows — may start project/onboard, project/press_release, or project/success" ;;
    ks-dev) printf '%s' "Keystone development — may start keystone_system/develop, keystone_system/issue, keystone_system/convention, or keystone_system/doctor" ;;
    *) return 1 ;;
  esac
}

# Derive a codex display name from the skill key. Falls back to title-casing
# the key after splitting on `.`, `_`, and `-` when no explicit mapping exists.
skill_display_name() {
  local key="$1"
  local dn
  if dn="$(command_display_name "$key" 2>/dev/null)"; then
    printf '%s' "$dn"
    return
  fi
  printf '%s' "$key" | tr '._-' '   ' | sed -E 's/(^|[[:space:]])([a-z])/\1\U\2/g'
}

# Copy colocated conventions and roles into a skill directory. Reads from the
# merged skill map (keystone defaults + optional consumer-flake overrides).
colocate_skill_conventions() {
  local skill_key="$1"
  local target_dir="$2"
  local conv_name src_file

  while IFS= read -r conv_name; do
    [[ -z "$conv_name" ]] && continue
    src_file="$conventions_dir/${conv_name}.md"
    [[ -f "$src_file" ]] && write_file "${target_dir}/${conv_name}.md" "$(cat "$src_file")"
  done < <(jq -r --arg k "$skill_key" '.[$k].colocated_conventions[]? // empty' <<< "$merged_skills_json")

  while IFS= read -r conv_name; do
    [[ -z "$conv_name" ]] && continue
    src_file="$conventions_dir/roles/${conv_name}.md"
    [[ -f "$src_file" ]] && write_file "${target_dir}/${conv_name}.md" "$(cat "$src_file")"
  done < <(jq -r --arg k "$skill_key" '.[$k].colocated_roles[]? // empty' <<< "$merged_skills_json")
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
  ks_allowed_routes_lines+=("- Personal assistant requests (reservations, birthdays, calendar, photo memories): direct the user to \`/ks-assistant\` instead of handling directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'notes'; then
  ks_allowed_routes_lines+=("- Notes workflows (repair, inbox, init, setup): direct the user to \`/ks-notes\` instead of starting a notes workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'project'; then
  ks_allowed_routes_lines+=("- Project workflows (onboard, press release, success): direct the user to \`/ks-projects\` instead of starting a project workflow directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'executive-assistant'; then
  ks_allowed_routes_lines+=("- Executive assistant workflows (calendar, inbox, events, portfolio reviews, task coordination): direct the user to \`/ks-ea\` instead of starting executive_assistant workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'engineer'; then
  ks_allowed_routes_lines+=("- Engineering workflows (implementation, code review, architecture, CI): direct the user to \`/ks-engineer\` instead of starting engineer workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'product'; then
  ks_allowed_routes_lines+=("- Product workflows (press releases, milestones, stakeholder communication): direct the user to \`/ks-product\` instead of starting project workflows directly.")
fi

if printf '%s\n' "${resolved_capabilities[@]}" | grep -qx 'project-manager'; then
  ks_allowed_routes_lines+=("- Project management workflows (task decomposition, tracking, boards): direct the user to \`/ks-project-manager\` instead of managing tasks directly.")
fi

repo_checkout="$(json_get '.repoCheckout')"
archetype="$(json_get '.archetype')"
development_mode="$(json_get '.developmentMode')"

if [[ "$repo_checkout" == "null" || -z "$repo_checkout" ]]; then
  echo "Error: manifest does not declare a live keystone repo checkout" >&2
  exit 1
fi

if [[ ! -d "$repo_checkout" ]]; then
  repo_slug="${repo_checkout##*/.keystone/repos/}"
  echo "Live keystone repo checkout not found at $repo_checkout — cloning $repo_slug..."
  mkdir -p "$(dirname "$repo_checkout")"
  git clone "https://github.com/$repo_slug.git" "$repo_checkout"
fi

conventions_dir="$repo_checkout/conventions"
templates_dir="$repo_checkout/modules/terminal/agent-assets"
archetypes_file="$conventions_dir/archetypes.yaml"

if [[ ! -f "$archetypes_file" ]]; then
  echo "Error: archetypes.yaml not found at $archetypes_file" >&2
  exit 1
fi

# Build the effective skill map: keystone defaults + optional consumer-flake
# overrides. User keys win wholesale (jq's `+` on objects replaces by key, no
# deep merge — KISS over field-level inheritance).
keystone_skills_json="$(yq -o json '.skills // {}' "$archetypes_file")"
if [[ -f "$USER_SKILLS_YAML" ]]; then
  user_skills_json="$(yq -o json '.skills // {}' "$USER_SKILLS_YAML")"
else
  user_skills_json='{}'
fi
merged_skills_json="$(jq -n --argjson a "$keystone_skills_json" --argjson b "$user_skills_json" '$a + $b')"

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
# Canonical instruction file lives in the consumer flake at _shared/AGENTS.md.
# Per-tool instruction filenames are symlinks pointing at it, so the three
# tools always read the same bytes. Consumer flakes commit _shared/AGENTS.md
# and gitignore the per-tool dirs (which contain only the symlink plus the
# rendered skills tree).
write_file "$CONSUMER_FLAKE_SHARED/AGENTS.md" "$global_agents_content"
mkdir -p "$CONSUMER_FLAKE_AGENTS/claude" "$CONSUMER_FLAKE_AGENTS/gemini" "$CONSUMER_FLAKE_AGENTS/codex"
ln -snf ../_shared/AGENTS.md "$CONSUMER_FLAKE_AGENTS/claude/CLAUDE.md"
ln -snf ../_shared/AGENTS.md "$CONSUMER_FLAKE_AGENTS/gemini/GEMINI.md"
ln -snf ../_shared/AGENTS.md "$CONSUMER_FLAKE_AGENTS/codex/AGENTS.md"
# OpenCode stays on the home dir for now (not yet wired into the symlink
# activation; future scope).
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
# Legacy single-skill cleanups (consumer-flake-resident now). If a user has a
# consumer-flake skill colliding with one of these legacy names, the deletion
# is visible in `git status` — `git checkout` restores it. Convention rule 15.
rm -rf "$CLAUDE_SKILLS_DEST/ks"
rm -rf "$CLAUDE_SKILLS_DEST/ks-pm"
rm -rf "$CLAUDE_SKILLS_DEST/ks-assistant"
rm -rf "$OPENCODE_SKILLS_DEST/ks"
rm -rf "$OPENCODE_SKILLS_DEST/ks-pm"
rm -rf "$OPENCODE_SKILLS_DEST/ks-assistant"

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
  rm -rf "$CODEX_SKILLS_DEST/$skill_name"
done

# Build the set of skills to render: the union of (manifest-published ks.*
# commands) and (always-on yaml keys). Always-on keys are anything in the
# merged skill map that doesn't start with `ks.` — deepwork-family entries
# and any user-authored additions in _shared/skills.yaml. ks.* keys are
# emitted only when published by the user's manifest.
skills_to_emit=()
declare -A seen_skills=()
while IFS= read -r yaml_key; do
  [[ -z "$yaml_key" ]] && continue
  if [[ "$yaml_key" != ks.* ]] && [[ -z "${seen_skills[$yaml_key]:-}" ]]; then
    skills_to_emit+=("$yaml_key")
    seen_skills[$yaml_key]=1
  fi
done < <(jq -r 'keys[]' <<< "$merged_skills_json")
for command_id in "${published_commands[@]}"; do
  [[ -z "$command_id" ]] && continue
  if [[ -z "${seen_skills[$command_id]:-}" ]]; then
    skills_to_emit+=("$command_id")
    seen_skills[$command_id]=1
  fi
done

for skill_key in "${skills_to_emit[@]}"; do
  description="$(command_description "$skill_key" || printf '%s' "")"
  display_name="$(skill_display_name "$skill_key" || printf '%s' "$skill_key")"
  if ! template_name="$(command_template_name "$skill_key" 2>/dev/null)"; then
    template_name=""
  fi
  if [[ -z "$template_name" ]]; then
    template_name="${skill_key//./-}-skill.template.md"
  fi
  template_path="$templates_dir/$template_name"
  if [[ ! -f "$template_path" ]]; then
    echo "Warning: skill '$skill_key' references missing template '$template_path'; skipping" >&2
    continue
  fi

  command_body="$(render_template "$template_path")"
  codex_name="$(codex_skill_name "$skill_key")"

  # Clean up legacy dash-named claude/gemini/opencode skill dirs that predate
  # the dotted-key naming.
  if [[ "$skill_key" != "$codex_name" ]]; then
    rm -rf "$CLAUDE_SKILLS_DEST/${codex_name}"
    rm -rf "$GEMINI_SKILLS_DEST/${codex_name}"
    rm -rf "$OPENCODE_SKILLS_DEST/${codex_name}"
  fi

  shared_skill_md="$(render_skill_md "$skill_key" "$description" "$command_body")"
  # Canonical committed skill body — Claude and Gemini get the identical
  # content rendered into their per-tool dirs (gitignored), but the
  # source-of-truth committed file lives here.
  write_file "$SHARED_SKILLS_DEST/${skill_key}/SKILL.md" "$shared_skill_md"
  colocate_skill_conventions "$skill_key" "$SHARED_SKILLS_DEST/${skill_key}"

  # Per-tool rendered copies (gitignored). Identical content to the canonical
  # `_shared/skills/<key>/` tree; emitted so each tool's loader (which reads
  # under its own `~/.<tool>/skills/<key>/`) finds the files at the path it
  # expects without traversing into `_shared/`.
  write_file "$CLAUDE_SKILLS_DEST/${skill_key}/SKILL.md" "$shared_skill_md"
  write_file "$GEMINI_SKILLS_DEST/${skill_key}/SKILL.md" "$shared_skill_md"
  write_file "$OPENCODE_SKILLS_DEST/${skill_key}/SKILL.md" "$shared_skill_md"

  codex_body="$(render_codex_skill_body "$command_body" "$codex_name")"
  codex_skill_md="$(render_skill_md "$codex_name" "$description" "$codex_body")"
  write_codex_skill "$codex_name" "$display_name" "$description" "$codex_skill_md" '
dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
'

  colocate_skill_conventions "$skill_key" "$CLAUDE_SKILLS_DEST/${skill_key}"
  colocate_skill_conventions "$skill_key" "$GEMINI_SKILLS_DEST/${skill_key}"
  colocate_skill_conventions "$skill_key" "$OPENCODE_SKILLS_DEST/${skill_key}"
  colocate_skill_conventions "$skill_key" "$CODEX_SKILLS_DEST/${codex_name}"
done
