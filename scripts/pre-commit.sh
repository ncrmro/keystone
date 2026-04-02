#!/usr/bin/env bash
# Tracked pre-commit hook for keystone.
# Runs nixfmt on staged .nix files and shellcheck on staged .sh files.
# Install: ln -sf ../../scripts/pre-commit.sh .git/hooks/pre-commit

set -euo pipefail

# Collect staged files (excludes deleted files via --diff-filter=d).
staged_nix_files="$(git diff --cached --name-only --diff-filter=d -- '*.nix')"
staged_sh_files="$(git diff --cached --name-only --diff-filter=d -- '*.sh')"

# --- nixfmt on staged .nix files ---
if [[ -n "$staged_nix_files" ]]; then
  if ! command -v nixfmt &>/dev/null; then
    echo "Error: nixfmt is not installed. Enter the devshell or install nixfmt." >&2
    exit 1
  fi

  echo "Running nixfmt on staged .nix files..."
  while IFS= read -r file; do
    [[ -f "$file" ]] && nixfmt "$file"
  done <<< "$staged_nix_files"

  # Restage only the files we formatted.
  echo "$staged_nix_files" | xargs git add --
fi

# --- shellcheck on staged .sh files ---
if [[ -n "$staged_sh_files" ]]; then
  if ! command -v shellcheck &>/dev/null; then
    echo "Error: shellcheck is not installed. Enter the devshell or install shellcheck." >&2
    exit 1
  fi

  echo "Running shellcheck on staged .sh files..."
  while IFS= read -r file; do
    [[ -f "$file" ]] && shellcheck --severity=error "$file"
  done <<< "$staged_sh_files"
fi
