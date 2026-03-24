#!/usr/bin/env bash
# generate-ai-artifacts — Deterministic generator for archetype-aware AI artifacts.
#
# Reads conventions/archetypes.yaml and convention markdown files to produce
# the ai-artifacts/ committed directory tree.  Output is deterministic: re-running
# without source changes produces identical files.
#
# Usage:
#   generate-ai-artifacts [--conventions-dir DIR] [--commands-dir DIR] [--output-dir DIR]
#
# Defaults:
#   --conventions-dir  conventions/       (relative to repo root)
#   --commands-dir     modules/terminal/ai-commands/
#   --output-dir       ai-artifacts/
#
# The generated tree looks like:
#   ai-artifacts/
#   ├── archetypes/<name>/
#   │   ├── claude/CLAUDE.md
#   │   ├── gemini/GEMINI.md
#   │   ├── codex/AGENTS.md
#   │   ├── opencode/AGENTS.md
#   │   └── skills/deepwork/SKILL.md
#   │   └── skills/<skill>/SKILL.md      (per archetype skill list)
#   └── roles/<role>/claude/agent.md      (per archetype role)

set -euo pipefail

# --- Defaults ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONVENTIONS_DIR="${SCRIPT_DIR}/../../conventions"
COMMANDS_DIR="${SCRIPT_DIR}/../../modules/terminal/ai-commands"
OUTPUT_DIR="${SCRIPT_DIR}/../../ai-artifacts"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --conventions-dir) CONVENTIONS_DIR="$2"; shift 2 ;;
    --commands-dir) COMMANDS_DIR="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ARCHETYPES_FILE="$CONVENTIONS_DIR/archetypes.yaml"

if [[ ! -f "$ARCHETYPES_FILE" ]]; then
  echo "Error: archetypes.yaml not found at $ARCHETYPES_FILE" >&2
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "Error: yq is required but not found in PATH." >&2
  exit 1
fi

# --- Helpers ---

# Compose instruction file content for an archetype.
# This mirrors the logic in modules/terminal/conventions.nix but runs at
# generation time so the output can be committed.
compose_instruction_file() {
  local archetype="$1"
  local description
  description=$(yq -r ".archetypes.$archetype.description // \"\"" "$ARCHETYPES_FILE")

  cat <<EOF
# Keystone Conventions

Archetype: **${archetype}**
${description}
EOF

  # Inline conventions
  local inlined_count
  inlined_count=$(yq ".archetypes.$archetype.inlined_conventions | length" "$ARCHETYPES_FILE" 2>/dev/null || echo "0")
  for ((i = 0; i < inlined_count; i++)); do
    local conv
    conv=$(yq -r ".archetypes.$archetype.inlined_conventions[$i]" "$ARCHETYPES_FILE")
    local conv_path="$CONVENTIONS_DIR/${conv}.md"
    if [[ -f "$conv_path" ]]; then
      echo ""
      echo "---"
      echo ""
      cat "$conv_path"
    else
      echo ""
      echo "<!-- Convention ${conv} not found -->"
    fi
  done

  # Referenced conventions
  local ref_count
  ref_count=$(yq ".archetypes.$archetype.referenced_conventions | length" "$ARCHETYPES_FILE" 2>/dev/null || echo "0")
  if [[ "$ref_count" -gt 0 ]]; then
    echo ""
    echo "---"
    echo ""
    echo "## Reference Conventions"
    echo ""
    echo "The following conventions are available for on-demand context:"
    echo ""
    for ((i = 0; i < ref_count; i++)); do
      local conv
      conv=$(yq -r ".archetypes.$archetype.referenced_conventions[$i]" "$ARCHETYPES_FILE")
      echo "- [${conv}](conventions/${conv}.md)"
    done
  fi
}

# Generate the DeepWork SKILL.md content (shared across tools)
generate_deepwork_skill() {
  cat <<'SKILL'
---
name: deepwork
description: "Start or continue DeepWork workflows using MCP tools"
---

# DeepWork Workflow Manager

Execute multi-step workflows with quality gate checkpoints.

## Terminology

A **job** is a collection of related **workflows**. For example, a "code_review" job
might contain workflows like "review_pr" and "review_diff". Users may use the terms
"job" and "workflow" somewhat interchangeably when describing the work they want done —
use context and the available workflows from `get_workflows` to determine the best match.

> **IMPORTANT**: Use the DeepWork MCP server tools. All workflow operations
> are performed through MCP tool calls and following the instructions they return,
> not by reading instructions from files.

## How to Use

1. Call `get_workflows` to discover available workflows
2. Call `start_workflow` with goal, job_name, and workflow_name
3. Follow the step instructions returned
4. Call `finished_step` with your outputs when done
5. Handle the response: `needs_work`, `next_step`, or `workflow_complete`

## Intent Parsing

When the user invokes `/deepwork`, parse their intent:
1. **ALWAYS**: Call `get_workflows` to discover available workflows
2. Based on the available flows and what the user said in their request, proceed:
    - **Explicit workflow**: `/deepwork <a workflow name>` → start the `<a workflow name>` workflow
    - **General request**: `/deepwork <a request>` → infer best match from available workflows
    - **No context**: `/deepwork` alone → ask user to choose from available workflows
SKILL
}

# Generate a command skill for a given command file.
# For Claude/Gemini/OpenCode this is a SKILL.md with frontmatter.
generate_command_skill() {
  local cmd_name="$1"
  local cmd_file="$COMMANDS_DIR/${cmd_name}.md"

  if [[ ! -f "$cmd_file" ]]; then
    echo "Warning: command template not found: $cmd_file" >&2
    return
  fi

  local first_line
  first_line=$(head -1 "$cmd_file" | sed 's/^# //' | sed 's/\.$//')
  local skill_name
  skill_name=$(echo "$cmd_name" | tr '.' '-')

  cat <<EOF
---
name: ${skill_name}
description: "${first_line}"
---

EOF
  cat "$cmd_file"
}

# Generate a Codex-specific skill (includes invocation instructions + agents/openai.yaml)
generate_codex_skill() {
  local cmd_name="$1"
  local cmd_file="$COMMANDS_DIR/${cmd_name}.md"

  if [[ ! -f "$cmd_file" ]]; then
    echo "Warning: command template not found: $cmd_file" >&2
    return
  fi

  local first_line
  first_line=$(head -1 "$cmd_file" | sed 's/^# //' | sed 's/\.$//')
  local skill_name
  skill_name=$(echo "$cmd_name" | tr '.' '-')
  local skill_token="\$${skill_name}"

  cat <<EOF
---
name: ${skill_name}
description: "${first_line}"
---

EOF
  cat "$cmd_file"
  cat <<EOF

## Codex skill invocation

Use this skill when the user invokes \`${skill_token}\` or asks for this workflow implicitly.
Interpret \`\$ARGUMENTS\` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
EOF
}

generate_codex_openai_yaml() {
  local cmd_name="$1"
  local cmd_file="$COMMANDS_DIR/${cmd_name}.md"

  if [[ ! -f "$cmd_file" ]]; then
    return
  fi

  local first_line
  first_line=$(head -1 "$cmd_file" | sed 's/^# //' | sed 's/\.$//')

  cat <<EOF
interface:
  display_name: "${first_line}"
  short_description: "${first_line}"

dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
EOF
}

# Generate a role agent profile for Claude-compatible tools.
generate_role_agent_profile() {
  local archetype="$1"
  local role="$2"
  local role_file="$CONVENTIONS_DIR/roles/${role}.md"

  echo "# Agent Profile: ${role}"
  echo ""
  echo "Archetype: ${archetype}"
  echo ""

  if [[ -f "$role_file" ]]; then
    cat "$role_file"
  fi

  echo ""
  echo "## Conventions"
  echo ""

  local conv_count
  conv_count=$(yq ".archetypes.$archetype.roles.$role.conventions | length" "$ARCHETYPES_FILE" 2>/dev/null || echo "0")
  for ((i = 0; i < conv_count; i++)); do
    local conv
    conv=$(yq -r ".archetypes.$archetype.roles.$role.conventions[$i]" "$ARCHETYPES_FILE")
    echo "- [${conv}](conventions/${conv}.md)"
  done
}

# --- Main generation ---

echo "Generating AI artifacts..."
echo "  Conventions: $CONVENTIONS_DIR"
echo "  Commands:    $COMMANDS_DIR"
echo "  Output:      $OUTPUT_DIR"

# Clean output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Get list of archetypes
ARCHETYPES=$(yq -r '.archetypes | keys | .[]' "$ARCHETYPES_FILE")

for archetype in $ARCHETYPES; do
  echo "  Archetype: $archetype"
  ARCH_DIR="$OUTPUT_DIR/archetypes/$archetype"

  # --- Tool-native instruction files (REQ-6) ---
  for tool_dir in claude gemini codex opencode; do
    mkdir -p "$ARCH_DIR/$tool_dir"
    case "$tool_dir" in
      claude)  compose_instruction_file "$archetype" > "$ARCH_DIR/$tool_dir/CLAUDE.md" ;;
      gemini)  compose_instruction_file "$archetype" > "$ARCH_DIR/$tool_dir/GEMINI.md" ;;
      codex)   compose_instruction_file "$archetype" > "$ARCH_DIR/$tool_dir/AGENTS.md" ;;
      opencode) compose_instruction_file "$archetype" > "$ARCH_DIR/$tool_dir/AGENTS.md" ;;
    esac
  done

  # --- DeepWork skill (always included, REQ-10) ---
  for tool_dir in claude gemini codex opencode; do
    mkdir -p "$ARCH_DIR/skills/deepwork"
    generate_deepwork_skill > "$ARCH_DIR/skills/deepwork/SKILL.md"
  done

  # Codex-specific DeepWork agent metadata
  mkdir -p "$ARCH_DIR/skills/deepwork/agents"
  cat > "$ARCH_DIR/skills/deepwork/agents/openai.yaml" <<'EOF'
interface:
  display_name: "DeepWork"
  short_description: "Start or continue DeepWork workflows using MCP tools"

dependencies:
  tools:
    - type: "mcp"
      value: "deepwork"
      description: "DeepWork MCP server"
EOF

  # --- Archetype-scoped skills from commands (REQ-7, REQ-10) ---
  skill_count=$(yq ".archetypes.$archetype.skills | length" "$ARCHETYPES_FILE" 2>/dev/null || echo "0")
  for ((s = 0; s < skill_count; s++)); do
    cmd_name=$(yq -r ".archetypes.$archetype.skills[$s]" "$ARCHETYPES_FILE")

    if [[ ! -f "$COMMANDS_DIR/${cmd_name}.md" ]]; then
      echo "    Warning: skill command not found: ${cmd_name}.md" >&2
      continue
    fi

    skill_name=$(echo "$cmd_name" | tr '.' '-')

    # Standard skill (Claude, Gemini, OpenCode)
    mkdir -p "$ARCH_DIR/skills/$skill_name"
    generate_command_skill "$cmd_name" > "$ARCH_DIR/skills/$skill_name/SKILL.md"

    # Codex-specific skill variant
    mkdir -p "$ARCH_DIR/skills/$skill_name/codex"
    generate_codex_skill "$cmd_name" > "$ARCH_DIR/skills/$skill_name/codex/SKILL.md"
    mkdir -p "$ARCH_DIR/skills/$skill_name/codex/agents"
    generate_codex_openai_yaml "$cmd_name" > "$ARCH_DIR/skills/$skill_name/codex/agents/openai.yaml"
  done

  # --- Role agent profiles (REQ-11) ---
  role_names=$(yq -r ".archetypes.$archetype.roles // {} | keys | .[]" "$ARCHETYPES_FILE" 2>/dev/null || true)
  for role in $role_names; do
    echo "    Role: $role"
    ROLE_DIR="$OUTPUT_DIR/roles/$role"
    mkdir -p "$ROLE_DIR/claude"
    generate_role_agent_profile "$archetype" "$role" > "$ROLE_DIR/claude/agent.md"
    # Gemini and OpenCode use the same format
    mkdir -p "$ROLE_DIR/gemini"
    cp "$ROLE_DIR/claude/agent.md" "$ROLE_DIR/gemini/agent.md"
    mkdir -p "$ROLE_DIR/opencode"
    cp "$ROLE_DIR/claude/agent.md" "$ROLE_DIR/opencode/agent.md"
    mkdir -p "$ROLE_DIR/codex"
    cp "$ROLE_DIR/claude/agent.md" "$ROLE_DIR/codex/agent.md"
  done
done

echo "Done. Generated artifacts in $OUTPUT_DIR"
