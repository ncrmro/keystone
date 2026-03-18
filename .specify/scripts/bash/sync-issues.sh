#!/usr/bin/env bash
# sync-issues.sh — Create GitHub issues for uncompleted tasks in a tasks.md file.
#
# Usage:
#   sync-issues.sh [--dry-run] [--label <label>] <tasks.md>
#   sync-issues.sh [--dry-run] [--label <label>]          # uses tasks.md in current feature dir
#
# Requirements: gh CLI authenticated (gh auth login)
#
# Behaviour:
#   - Reads every unchecked task line ("- [ ] ...") from the given tasks.md
#   - Skips lines that already contain a GitHub issue URL (https://github.com/.*/issues/\d+)
#   - Creates a GitHub issue for each new uncompleted task
#   - Appends the issue URL to the task line so subsequent runs are idempotent
#
# Options:
#   --dry-run    Print what would be created without actually calling gh
#   --label L    Apply label L to every created issue (can be repeated)
#   --help       Show this help

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DRY_RUN=false
LABELS=()
TASKS_FILE=""

usage() {
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --label)
            shift
            LABELS+=("$1")
            ;;
        --help|-h) usage ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) TASKS_FILE="$1" ;;
    esac
    shift
done

# Default to feature tasks.md if not provided
if [[ -z "$TASKS_FILE" ]]; then
    eval "$(get_feature_paths)"
    TASKS_FILE="$TASKS"
fi

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "Error: tasks file not found: $TASKS_FILE" >&2
    exit 1
fi

# Check gh CLI is available
if ! command -v gh &>/dev/null; then
    echo "Error: 'gh' CLI not found. Install from https://cli.github.com/" >&2
    exit 1
fi

# Determine repo from git remote (gh uses this automatically)
REPO_ROOT=$(get_repo_root)
cd "$REPO_ROOT"

# Derive a label from the spec directory name if no label provided
if [[ ${#LABELS[@]} -eq 0 ]]; then
    SPEC_DIR=$(dirname "$TASKS_FILE")
    SPEC_NAME=$(basename "$SPEC_DIR")
    LABELS=("spec:$SPEC_NAME")
fi

# Build label flags for gh
LABEL_FLAGS=()
for label in "${LABELS[@]}"; do
    LABEL_FLAGS+=(--label "$label")
done

created=0
skipped=0
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

# Read tasks.md line by line; process unchecked tasks
while IFS= read -r line; do
    # Match unchecked task: "- [ ] ..."
    if [[ "$line" =~ ^[[:space:]]*-\ \[\ \][[:space:]]+(.*) ]]; then
        task_text="${BASH_REMATCH[1]}"

        # Skip if already linked to a GitHub issue
        if echo "$task_text" | grep -qE 'https://github\.com/[^/]+/[^/]+/issues/[0-9]+'; then
            echo "  skip (already linked): $task_text"
            echo "$line" >> "$tmpfile"
            ((skipped++)) || true
            continue
        fi

        # Extract issue title: strip leading task ID (e.g. "T001 [P] [US1] ...")
        title=$(echo "$task_text" | sed -E 's/^[A-Z0-9]+[[:space:]](\[[^]]*\][[:space:]])*//; s/[[:space:]]+$//') 

        # Use full task text if extraction produced empty string
        [[ -z "$title" ]] && title="$task_text"

        if $DRY_RUN; then
            echo "  [dry-run] would create issue: $title"
            echo "$line" >> "$tmpfile"
        else
            echo "  creating issue: $title"
            issue_url=$(gh issue create \
                --title "$title" \
                --body "Task from \`$TASKS_FILE\`

\`\`\`
$task_text
\`\`\`" \
                "${LABEL_FLAGS[@]}" \
                --assignee "@me" 2>/dev/null || \
                gh issue create \
                --title "$title" \
                --body "Task from \`$TASKS_FILE\`

\`\`\`
$task_text
\`\`\`" \
                "${LABEL_FLAGS[@]}" 2>/dev/null)

            echo "    → $issue_url"
            # Append issue URL to task line
            echo "${line} ${issue_url}" >> "$tmpfile"
            ((created++)) || true
        fi
    else
        echo "$line" >> "$tmpfile"
    fi
done < "$TASKS_FILE"

if ! $DRY_RUN && [[ $created -gt 0 ]]; then
    cp "$tmpfile" "$TASKS_FILE"
    echo ""
    echo "✓ Created $created issue(s), skipped $skipped already-linked task(s)."
    echo "  Task file updated with issue URLs: $TASKS_FILE"
else
    echo ""
    echo "Summary: $created created, $skipped skipped."
fi
