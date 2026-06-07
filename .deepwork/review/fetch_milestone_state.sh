#!/usr/bin/env bash
# Precompute script for the milestone_github_sync .deepreview rule.
# Detects which docs/milestones/M*/ dirs have changed files, parses each
# README.md's YAML frontmatter, and dumps the matching GitHub milestone +
# tracker issue + attached issue list. Output is injected as the reviewer's
# "Precomputed Context" so a single review pass can compare local vs remote.
set -euo pipefail

REPO="ncrmro/keystone"

# Mirror deepreview's changed-file detection: committed-on-branch + staged +
# unstaged + untracked.
{
  git diff --name-only --diff-filter=AMR origin/main...HEAD 2>/dev/null || true
  git diff --name-only --diff-filter=AMR --cached 2>/dev/null || true
  git diff --name-only --diff-filter=AMR 2>/dev/null || true
  git ls-files --others --exclude-standard 2>/dev/null || true
} > /tmp/.milestone_changed_files.$$
dirs=$(grep -E '^docs/milestones/M[0-9]+-[^/]+/' /tmp/.milestone_changed_files.$$ \
       | awk -F/ '{print $1"/"$2"/"$3}' \
       | sort -u)
rm -f /tmp/.milestone_changed_files.$$

if [ -z "$dirs" ]; then
  echo "No milestone files changed."
  exit 0
fi

for dir in $dirs; do
  readme="$dir/README.md"
  if [ ! -f "$readme" ]; then
    echo "=== $dir ==="
    echo "ERROR: README.md missing — cannot resolve trackerMilestone."
    continue
  fi

  # Frontmatter = lines between the first two `---` markers.
  fm=$(awk '/^---[[:space:]]*$/{c++; if (c==2) exit; next} c==1' "$readme")
  if [ -z "$fm" ]; then
    echo "=== $dir ==="
    echo "ERROR: README.md has no YAML frontmatter."
    continue
  fi

  trackerMilestone=$(printf '%s\n' "$fm" | yq '.trackerMilestone // "null"')
  trackerIssue=$(printf '%s\n' "$fm" | yq '.trackerIssue // "null"')
  status=$(printf '%s\n' "$fm" | yq '.status // "null"')
  slug=$(printf '%s\n' "$fm" | yq '.slug // "null"')

  echo "=== $dir ==="
  echo "Local frontmatter: slug=$slug trackerMilestone=$trackerMilestone trackerIssue=$trackerIssue status=$status"
  echo

  if [ "$trackerMilestone" = "null" ] || [ -z "$trackerMilestone" ]; then
    echo "ERROR: frontmatter has no trackerMilestone — cannot fetch GitHub state."
    continue
  fi

  echo "--- gh api repos/$REPO/milestones/$trackerMilestone ---"
  if ! gh api "repos/$REPO/milestones/$trackerMilestone" \
       --jq '{title, state, description, open_issues, closed_issues, due_on, html_url}' 2>&1; then
    echo "ERROR: failed to fetch GitHub milestone $trackerMilestone."
    continue
  fi
  echo

  if [ "$trackerIssue" != "null" ] && [ -n "$trackerIssue" ]; then
    echo "--- gh api repos/$REPO/issues/$trackerIssue ---"
    gh api "repos/$REPO/issues/$trackerIssue" \
       --jq '{number, state, title, milestone_number: (.milestone.number // null), body_first_2k: (.body[0:2000])}' 2>&1 || \
       echo "ERROR: failed to fetch tracker issue $trackerIssue."
    echo
  fi

  ms_title=$(gh api "repos/$REPO/milestones/$trackerMilestone" --jq '.title' 2>/dev/null || true)
  if [ -n "$ms_title" ]; then
    echo "--- gh issue list --milestone \"$ms_title\" --state all ---"
    gh issue list --repo "$REPO" --milestone "$ms_title" --state all --limit 60 \
       --json number,title,state \
       --jq 'sort_by(.state, -.number) | .[] |
             "[\(.state)] #\(.number) — \(.title)"' 2>&1 || \
       echo "ERROR: failed to list issues for milestone \"$ms_title\"."
    echo
  fi
done
