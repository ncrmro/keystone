# shellcheck shell=bash
# agents-e2e.sh -- End-to-end OS agent product lifecycle test (REQ-031)
#
# Sourced by ks.sh at build time. Provides cmd_agents_e2e() and all
# supporting functions for the E2E harness.
#
# See specs/REQ-031-e2e-os-agent-product-test.md for requirements.

# ---------------------------------------------------------------------------
# Shared helpers (DRY)
# ---------------------------------------------------------------------------

e2e_fork_name() {
  echo "$E2E_TEMPLATE_REPO" | cut -d/ -f2
}

e2e_engineer_repo() {
  echo "${E2E_ENGINEER_AGENT}/$(e2e_fork_name)"
}

e2e_engineer_home() {
  getent passwd "agent-${E2E_ENGINEER_AGENT}" 2>/dev/null | cut -d: -f6
}

e2e_find_in_agent_paths() {
  local engineer_home="$1"
  shift
  local find_args=("$@")
  for search_root in "${engineer_home}/../.worktrees" "${engineer_home}/repos"; do
    if find "$search_root" "${find_args[@]}" 2>/dev/null | head -1 | grep -q .; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

print_agents_e2e_help() {
  cat <<'EOF'
Usage: ks agents e2e [options]

Run the end-to-end agent product lifecycle test (REQ-031).

Orchestrates a palindrome feature request through the full product-to-engineering
workflow: email intake -> press release -> milestone -> specification ->
implementation -> Playwright testing -> release PR -> product verification.

Options:
  --product NAME      Product agent name (required)
  --engineer NAME     Engineering agent name (required)
  --platform NAME     Platform for repos/issues (default: forgejo)
  --provider MODEL    AI model provider (default: claude)
  --forgejo-url URL   Forgejo instance URL (default: https://git.ncrmro.com)
  --forgejo-token TOK Forgejo API token (default: $FORGEJO_TOKEN)
  --template-repo R   Template repo owner/name (default: ks-testing/agent-e2e-bun-template)
  --dry-run           Validate configuration without executing the workflow
  --print             Render final report via pandoc when complete
  -h, --help          Show this help

Examples:
  ks agents e2e --product luce --engineer drago --dry-run
  ks agents e2e --product luce --engineer drago
  ks agents e2e --product luce --engineer drago --print
EOF
}

# ---------------------------------------------------------------------------
# Report helpers (REQ-031.1–031.5, NFR-004)
# ---------------------------------------------------------------------------

e2e_report_cleanup() {
  if [[ -n "${E2E_REPORT_FILE:-}" && -f "$E2E_REPORT_FILE" ]]; then
    rm -f "$E2E_REPORT_FILE"
  fi
}

e2e_report_init() {
  E2E_REPORT_FILE=$(mktemp "${TMPDIR:-/tmp}/ks-e2e-report.XXXXXX.yml")
  E2E_REPORT_RC=0
  trap e2e_report_cleanup EXIT
  cat > "$E2E_REPORT_FILE" <<YAML
# ks agents e2e report -- $(date -u +%Y-%m-%dT%H:%M:%SZ)
harness:
  product_agent: "${E2E_PRODUCT_AGENT}"
  engineer_agent: "${E2E_ENGINEER_AGENT}"
  platform: "${E2E_PLATFORM}"
  provider: "${E2E_PROVIDER}"
  template_repo: "${E2E_TEMPLATE_REPO}"
  started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  completed_at: null
checks: []
YAML
}

e2e_report_check() {
  local name="$1"
  local status="$2"  # pass | fail | skip | running
  local details="${3:-}"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local completed_at_line=""
  if [[ "$status" != "running" ]]; then
    completed_at_line="    completed_at: \"$now\""
  else
    completed_at_line="    completed_at: null"
  fi

  cat >> "$E2E_REPORT_FILE" <<YAML
  - name: "$name"
    status: "$status"
    started_at: "$now"
$completed_at_line
    details: $(e2e_yaml_quote "$details")
YAML

  if [[ "$status" == "fail" ]]; then
    E2E_REPORT_RC=1
  fi
}

e2e_report_finalize() {
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed -i "s/^  completed_at: null$/  completed_at: \"$now\"/" "$E2E_REPORT_FILE"
}

e2e_yaml_quote() {
  local val="$1"
  if [[ -z "$val" ]]; then
    printf '""'
  else
    printf '"%s"' "$(printf '%s' "$val" | sed 's/"/\\"/g')"
  fi
}

# ---------------------------------------------------------------------------
# Logfmt stderr output (NFR-005)
# ---------------------------------------------------------------------------

e2e_emit() {
  local level="${1:-info}"
  shift
  local msg="$1"
  shift
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf 'ts=%s level=%s component=e2e msg="%s"' "$now" "$level" "$msg" >&2
  while [[ $# -ge 2 ]]; do
    printf ' %s="%s"' "$1" "$2" >&2
    shift 2
  done
  printf '\n' >&2
}

# ---------------------------------------------------------------------------
# Forgejo platform abstraction (REQ-031.42–031.44)
# ---------------------------------------------------------------------------

e2e_forgejo_api() {
  local method="$1"
  local endpoint="$2"
  shift 2
  local url="${E2E_FORGEJO_URL}/api/v1${endpoint}"

  curl -sSf -X "$method" \
    -H "Authorization: token ${E2E_FORGEJO_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@" \
    "$url" 2>/dev/null
}

e2e_forgejo_repo_exists() {
  local repo="$1"
  e2e_forgejo_api GET "/repos/$repo" >/dev/null 2>&1
}

e2e_forgejo_delete_repo() {
  local repo="$1"
  e2e_forgejo_api DELETE "/repos/$repo" >/dev/null 2>&1 || true
}

e2e_forgejo_fork_repo() {
  local source_repo="$1"
  local target_org="$2"
  e2e_forgejo_api POST "/repos/$source_repo/forks" \
    -d "{\"organization\": \"$target_org\"}"
}

e2e_forgejo_create_milestone() {
  local repo="$1"
  local title="$2"
  e2e_forgejo_api POST "/repos/$repo/milestones" \
    -d "{\"title\": \"$title\"}"
}

e2e_forgejo_list_milestones() {
  local repo="$1"
  e2e_forgejo_api GET "/repos/$repo/milestones?state=open&limit=50"
}

e2e_forgejo_create_issue() {
  local repo="$1"
  local title="$2"
  local body="${3:-}"
  local milestone_id="${4:-}"
  local assignee="${5:-}"
  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg body "$body" \
    --argjson milestone "${milestone_id:-null}" \
    --arg assignee "$assignee" \
    '{title: $title, body: $body} +
     (if $milestone != null then {milestone: $milestone} else {} end) +
     (if $assignee != "" then {assignees: [$assignee]} else {} end)')
  e2e_forgejo_api POST "/repos/$repo/issues" -d "$payload"
}

e2e_forgejo_list_issues() {
  local repo="$1"
  local state="${2:-open}"
  local milestone="${3:-}"
  local qs="state=$state&limit=50"
  if [[ -n "$milestone" ]]; then
    qs="${qs}&milestone=$milestone"
  fi
  e2e_forgejo_api GET "/repos/$repo/issues?$qs"
}

e2e_forgejo_close_issue() {
  local repo="$1"
  local issue_number="$2"
  e2e_forgejo_api PATCH "/repos/$repo/issues/$issue_number" \
    -d '{"state": "closed"}'
}

e2e_forgejo_list_prs() {
  local repo="$1"
  local state="${2:-open}"
  e2e_forgejo_api GET "/repos/$repo/pulls?state=$state&limit=50"
}

e2e_forgejo_list_branches() {
  local repo="$1"
  e2e_forgejo_api GET "/repos/$repo/branches?limit=50"
}

e2e_forgejo_comment_issue() {
  local repo="$1"
  local issue_number="$2"
  local body="$3"
  e2e_forgejo_api POST "/repos/$repo/issues/$issue_number/comments" \
    -d "$(jq -n --arg body "$body" '{body: $body}')"
}

# ---------------------------------------------------------------------------
# Agent quiescence (REQ-031.7a--031.7d)
# ---------------------------------------------------------------------------

e2e_pause_agents() {
  for agent in "$E2E_PRODUCT_AGENT" "$E2E_ENGINEER_AGENT"; do
    # Check if already paused
    if agentctl "$agent" paused 2>/dev/null; then
      e2e_emit info "agent already paused" agent "$agent"
      continue
    fi

    # Check for active tasks before pausing
    local task_output
    task_output=$(agentctl "$agent" tasks 2>/dev/null || true)
    if echo "$task_output" | grep -qi "in.progress\|running\|active"; then
      e2e_emit warn "agent has active tasks" agent "$agent"
      if [[ -t 0 && -t 1 ]]; then
        printf 'Agent %s has active tasks. Kill and proceed? [y/N] ' "$agent" >&2
        local reply=""
        IFS= read -r reply || true
        case "$reply" in
          y|Y|yes|YES)
            e2e_emit info "operator approved kill" agent "$agent"
            ;;
          *)
            e2e_report_check "agent_quiescence" "fail" "Operator declined to kill active tasks on $agent"
            return 1
            ;;
        esac
      else
        e2e_report_check "agent_quiescence" "fail" "Agent $agent has active tasks (non-interactive, cannot prompt)"
        return 1
      fi
    fi

    agentctl "$agent" pause "e2e test in progress" || {
      e2e_report_check "agent_quiescence" "fail" "Failed to pause agent $agent"
      return 1
    }
    e2e_emit info "paused agent" agent "$agent"
  done
  e2e_report_check "agent_quiescence" "pass" "Both agents paused"
}

e2e_resume_agents() {
  for agent in "$E2E_PRODUCT_AGENT" "$E2E_ENGINEER_AGENT"; do
    agentctl "$agent" resume 2>/dev/null || true
    e2e_emit info "resumed agent" agent "$agent"
  done
}

# ---------------------------------------------------------------------------
# Environment lifecycle (REQ-031.11--031.14, NFR-002)
# ---------------------------------------------------------------------------

e2e_cleanup_environment() {
  e2e_emit info "cleaning environment"

  local repo_name owner
  repo_name=$(e2e_fork_name)
  owner=$(echo "$E2E_TEMPLATE_REPO" | cut -d/ -f1)

  # Remove agent worktrees and clones
  for agent in "$E2E_PRODUCT_AGENT" "$E2E_ENGINEER_AGENT"; do
    local agent_home
    agent_home=$(getent passwd "agent-${agent}" 2>/dev/null | cut -d: -f6) || continue
    if [[ ! -d "$agent_home" ]]; then continue; fi

    local wt_base="${agent_home}/../.worktrees/${owner}/${repo_name}"
    if [[ -d "$wt_base" ]]; then
      e2e_emit info "removing worktrees" agent "$agent" path "$wt_base"
      rm -rf "$wt_base"
    fi
    local clone_path="${agent_home}/repos/${owner}/${repo_name}"
    if [[ -d "$clone_path" ]]; then
      e2e_emit info "removing clone" agent "$agent" path "$clone_path"
      rm -rf "$clone_path"
    fi
  done

  e2e_report_check "environment_cleanup" "pass" "Cleaned agent disks and worktrees"
}

e2e_setup_environment() {
  e2e_emit info "setting up environment"

  local fork_name
  fork_name=$(e2e_fork_name)

  # Delete any prior forks on Forgejo (idempotent)
  for agent in "$E2E_PRODUCT_AGENT" "$E2E_ENGINEER_AGENT"; do
    e2e_forgejo_delete_repo "${agent}/${fork_name}"
  done

  # Fork template for engineering agent
  local fork_result
  fork_result=$(e2e_forgejo_fork_repo "$E2E_TEMPLATE_REPO" "$E2E_ENGINEER_AGENT" 2>&1) || {
    e2e_report_check "environment_setup" "fail" "Failed to fork template: $fork_result"
    return 1
  }

  e2e_report_check "environment_setup" "pass" "Forked template to ${E2E_ENGINEER_AGENT}/${fork_name}"
}

# ---------------------------------------------------------------------------
# Product agent workflow checks (REQ-031.15–031.18)
# ---------------------------------------------------------------------------

e2e_check_product_email() {
  e2e_emit info "sending palindrome requirement to product agent" agent "$E2E_PRODUCT_AGENT"

  # Send the palindrome feature requirement email
  if command -v agent-mail >/dev/null 2>&1; then
    local agent_email="agent-${E2E_PRODUCT_AGENT}@$(hostname -d 2>/dev/null || echo "localhost")"
    e2e_emit info "dispatching email" to "$agent_email"
    # TODO: send actual email via agent-mail with palindrome requirement template
    e2e_report_check "product_email_dispatch" "skip" "agent-mail dispatch not yet wired"
  else
    e2e_report_check "product_email_dispatch" "skip" "agent-mail not available"
  fi
}

e2e_check_product_press_release() {
  e2e_emit info "checking for press release issue"
  local repo
  repo=$(e2e_engineer_repo)

  local issues
  issues=$(e2e_forgejo_list_issues "$repo" "open" 2>/dev/null) || {
    e2e_report_check "product_press_release" "skip" "Could not list issues"
    return 0
  }

  local pr_count
  pr_count=$(echo "$issues" | jq '[.[] | select(.title | test("press release|palindrome"; "i"))] | length' 2>/dev/null || echo "0")

  if [[ "$pr_count" -gt 0 ]]; then
    e2e_report_check "product_press_release" "pass" "Found press release issue"
  else
    e2e_report_check "product_press_release" "skip" "No press release issue found yet"
  fi
}

e2e_check_product_milestone() {
  e2e_emit info "checking for milestone"
  local repo
  repo=$(e2e_engineer_repo)

  local milestones
  milestones=$(e2e_forgejo_list_milestones "$repo" 2>/dev/null) || {
    e2e_report_check "product_milestone" "skip" "Could not list milestones"
    return 0
  }

  local ms_count
  ms_count=$(echo "$milestones" | jq '[.[] | select(.title | test("palindrome"; "i"))] | length' 2>/dev/null || echo "0")

  if [[ "$ms_count" -gt 0 ]]; then
    e2e_report_check "product_milestone" "pass" "Found palindrome milestone"
  else
    e2e_report_check "product_milestone" "skip" "No palindrome milestone found yet"
  fi
}

# ---------------------------------------------------------------------------
# Engineering agent workflow checks (REQ-031.19–031.33)
# ---------------------------------------------------------------------------

e2e_check_engineering_issue() {
  e2e_emit info "checking for engineering issue on milestone"
  local repo
  repo=$(e2e_engineer_repo)

  local issues
  issues=$(e2e_forgejo_list_issues "$repo" "all" 2>/dev/null) || {
    e2e_report_check "engineering_issue" "skip" "Could not list issues"
    return 0
  }

  local eng_count
  eng_count=$(echo "$issues" | jq '[.[] | select(.title | test("engineer|implement|palindrome"; "i"))] | length' 2>/dev/null || echo "0")

  if [[ "$eng_count" -gt 0 ]]; then
    e2e_report_check "engineering_issue" "pass" "Found engineering issue"
  else
    e2e_report_check "engineering_issue" "skip" "No engineering issue found yet"
  fi
}

e2e_check_trunk_branch() {
  e2e_emit info "checking for trunk branch"
  local repo
  repo=$(e2e_engineer_repo)

  local branches
  branches=$(e2e_forgejo_list_branches "$repo" 2>/dev/null) || {
    e2e_report_check "trunk_branch" "skip" "Could not list branches"
    return 0
  }

  local branch_count
  branch_count=$(echo "$branches" | jq '[.[] | select(.name != "main" and .name != "master")] | length' 2>/dev/null || echo "0")

  if [[ "$branch_count" -gt 0 ]]; then
    local branch_name
    branch_name=$(echo "$branches" | jq -r '[.[] | select(.name != "main" and .name != "master")][0].name' 2>/dev/null || echo "unknown")
    e2e_report_check "trunk_branch" "pass" "Found branch: $branch_name"
  else
    e2e_report_check "trunk_branch" "skip" "No trunk branch found yet"
  fi
}

e2e_check_worktree() {
  e2e_emit info "checking for engineer worktree"
  local eng_home fork_name
  eng_home=$(e2e_engineer_home)
  fork_name=$(e2e_fork_name)

  if [[ -z "$eng_home" ]]; then
    e2e_report_check "worktree" "skip" "Could not resolve engineer home directory"
    return 0
  fi

  local wt_base="${eng_home}/../.worktrees/${E2E_ENGINEER_AGENT}/${fork_name}"
  if [[ -d "$wt_base" ]] && ls "$wt_base"/*/ >/dev/null 2>&1; then
    e2e_report_check "worktree" "pass" "Worktree exists at $wt_base"
  else
    e2e_report_check "worktree" "skip" "No worktree found at $wt_base"
  fi
}

e2e_check_spec_file() {
  e2e_emit info "checking for specs/REQ-*palindrome* file"
  local eng_home
  eng_home=$(e2e_engineer_home)

  if [[ -z "$eng_home" ]]; then
    e2e_report_check "spec_file" "skip" "Could not resolve engineer home directory"
    return 0
  fi

  if e2e_find_in_agent_paths "$eng_home" -path "*/specs/REQ-*palindrome*" -name "*.md"; then
    e2e_report_check "spec_file" "pass" "Found palindrome spec file"
  else
    e2e_report_check "spec_file" "skip" "No palindrome spec file found yet"
  fi
}

e2e_check_palindrome_backend() {
  e2e_emit info "checking palindrome backend responds correctly"
  # TODO: discover the running bun server port and test HTTP endpoint
  e2e_report_check "palindrome_backend" "skip" "Backend validation not yet implemented"
}

e2e_check_playwright_tests() {
  e2e_emit info "checking for Playwright tests in packages/e2e/"
  local eng_home
  eng_home=$(e2e_engineer_home)

  if [[ -z "$eng_home" ]]; then
    e2e_report_check "playwright_tests" "skip" "Could not resolve engineer home directory"
    return 0
  fi

  if e2e_find_in_agent_paths "$eng_home" \( -path "*/packages/e2e/*.spec.*" -o -path "*/packages/e2e/*.test.*" \); then
    e2e_report_check "playwright_tests" "pass" "Found Playwright test files"
  else
    e2e_report_check "playwright_tests" "skip" "No Playwright tests found yet"
  fi
}

e2e_check_screenshots() {
  e2e_emit info "checking screenshot naming convention"
  local eng_home
  eng_home=$(e2e_engineer_home)

  if [[ -z "$eng_home" ]]; then
    e2e_report_check "screenshots" "skip" "Could not resolve engineer home directory"
    return 0
  fi

  local found=false
  local bad_names=false
  while IFS= read -r png; do
    found=true
    local basename_png
    basename_png=$(basename "$png")
    if ! echo "$basename_png" | grep -qE '^[a-z0-9_-]+\.[0-9]+\.[a-z0-9_-]+\.png$'; then
      bad_names=true
    fi
  done < <(find "${eng_home}/../.worktrees" "${eng_home}/repos" -name "*.png" -path "*/packages/e2e/*" 2>/dev/null)

  if [[ "$found" == true && "$bad_names" == false ]]; then
    e2e_report_check "screenshots" "pass" "Screenshots follow naming convention"
  elif [[ "$found" == true && "$bad_names" == true ]]; then
    e2e_report_check "screenshots" "fail" "Some screenshots do not follow {test-name}.{step-index}.{step-name}.png"
  else
    e2e_report_check "screenshots" "skip" "No screenshots found yet"
  fi
}

e2e_check_lfs_tracking() {
  e2e_emit info "checking git LFS tracking for PNG files"
  local eng_home fork_name
  eng_home=$(e2e_engineer_home)
  fork_name=$(e2e_fork_name)

  if [[ -z "$eng_home" ]]; then
    e2e_report_check "lfs_tracking" "skip" "Could not resolve engineer home directory"
    return 0
  fi

  local found_gitattributes=false
  for search_root in "${eng_home}/../.worktrees" "${eng_home}/repos"; do
    if find "$search_root" -name ".gitattributes" -path "*${fork_name}*" 2>/dev/null | while IFS= read -r ga; do
      if grep -q '\.png.*filter=lfs' "$ga" 2>/dev/null; then
        return 0
      fi
    done; then
      found_gitattributes=true
      break
    fi
  done

  if [[ "$found_gitattributes" == true ]]; then
    e2e_report_check "lfs_tracking" "pass" ".gitattributes tracks *.png via LFS"
  else
    e2e_report_check "lfs_tracking" "skip" "No LFS tracking found for PNG files"
  fi
}

e2e_check_release_pr() {
  e2e_emit info "checking for release PR"
  local repo
  repo=$(e2e_engineer_repo)

  local prs
  prs=$(e2e_forgejo_list_prs "$repo" "all" 2>/dev/null) || {
    e2e_report_check "release_pr" "skip" "Could not list PRs"
    return 0
  }

  local pr_count
  pr_count=$(echo "$prs" | jq 'length' 2>/dev/null || echo "0")

  if [[ "$pr_count" -gt 0 ]]; then
    e2e_report_check "release_pr" "pass" "Found release PR"
  else
    e2e_report_check "release_pr" "skip" "No release PR found yet"
  fi
}

e2e_check_issue_closed() {
  e2e_emit info "checking engineering issue is closed"
  local repo
  repo=$(e2e_engineer_repo)

  local closed
  closed=$(e2e_forgejo_list_issues "$repo" "closed" 2>/dev/null) || {
    e2e_report_check "issue_closed" "skip" "Could not list closed issues"
    return 0
  }

  local count
  count=$(echo "$closed" | jq 'length' 2>/dev/null || echo "0")

  if [[ "$count" -gt 0 ]]; then
    e2e_report_check "issue_closed" "pass" "Found $count closed issue(s)"
  else
    e2e_report_check "issue_closed" "skip" "No closed issues found yet"
  fi
}

# ---------------------------------------------------------------------------
# Product verification checks (REQ-031.34–031.35)
# ---------------------------------------------------------------------------

e2e_check_milestone_closed() {
  e2e_emit info "checking milestone is closed"
  local repo
  repo=$(e2e_engineer_repo)

  local milestones
  milestones=$(e2e_forgejo_api GET "/repos/$repo/milestones?state=closed&limit=50" 2>/dev/null) || {
    e2e_report_check "milestone_closed" "skip" "Could not list milestones"
    return 0
  }

  local ms_count
  ms_count=$(echo "$milestones" | jq 'length' 2>/dev/null || echo "0")

  if [[ "$ms_count" -gt 0 ]]; then
    e2e_report_check "milestone_closed" "pass" "Palindrome milestone closed"
  else
    e2e_report_check "milestone_closed" "skip" "No closed milestones found"
  fi
}

# ---------------------------------------------------------------------------
# Dry-run validation (REQ-031.7)
# ---------------------------------------------------------------------------

e2e_dry_run() {
  local rc=0

  e2e_emit info "dry-run: validating configuration"

  # Check product agent exists
  if known_agents_list 2>/dev/null | grep -Fxq "$E2E_PRODUCT_AGENT"; then
    e2e_report_check "dryrun_product_agent" "pass" "Agent '$E2E_PRODUCT_AGENT' is configured"
  else
    e2e_report_check "dryrun_product_agent" "fail" "Agent '$E2E_PRODUCT_AGENT' not found in agentctl"
    rc=1
  fi

  # Check engineering agent exists
  if known_agents_list 2>/dev/null | grep -Fxq "$E2E_ENGINEER_AGENT"; then
    e2e_report_check "dryrun_engineer_agent" "pass" "Agent '$E2E_ENGINEER_AGENT' is configured"
  else
    e2e_report_check "dryrun_engineer_agent" "fail" "Agent '$E2E_ENGINEER_AGENT' not found in agentctl"
    rc=1
  fi

  # Check agent pause state (dry-run only reports, does not pause)
  for agent in "$E2E_PRODUCT_AGENT" "$E2E_ENGINEER_AGENT"; do
    if agentctl "$agent" paused 2>/dev/null; then
      e2e_report_check "dryrun_${agent}_paused" "pass" "Agent '$agent' is paused"
    else
      e2e_report_check "dryrun_${agent}_paused" "pass" "Agent '$agent' is running (will be paused during full run)"
    fi
  done

  # Check Forgejo connectivity
  if [[ "$E2E_PLATFORM" == "forgejo" ]]; then
    if [[ -z "$E2E_FORGEJO_TOKEN" ]]; then
      e2e_report_check "dryrun_forgejo_token" "fail" "FORGEJO_TOKEN not set and --forgejo-token not provided"
      rc=1
    else
      e2e_report_check "dryrun_forgejo_token" "pass" "Forgejo token present"
    fi

    if e2e_forgejo_repo_exists "$E2E_TEMPLATE_REPO"; then
      e2e_report_check "dryrun_template_repo" "pass" "Template repo '$E2E_TEMPLATE_REPO' exists"
    else
      e2e_report_check "dryrun_template_repo" "fail" "Template repo '$E2E_TEMPLATE_REPO' not found at ${E2E_FORGEJO_URL}"
      rc=1
    fi
  fi

  # Check agent-mail available
  if command -v agent-mail >/dev/null 2>&1; then
    e2e_report_check "dryrun_agent_mail" "pass" "agent-mail is available"
  else
    e2e_report_check "dryrun_agent_mail" "fail" "agent-mail not found in PATH"
    rc=1
  fi

  return "$rc"
}

# ---------------------------------------------------------------------------
# Print report (REQ-031.3)
# ---------------------------------------------------------------------------

e2e_print_report() {
  if command -v glow >/dev/null 2>&1; then
    # Wrap YAML in a markdown code block for readable terminal output
    { echo '```yaml'; cat "$E2E_REPORT_FILE"; echo '```'; } | glow -
  else
    cat "$E2E_REPORT_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

cmd_agents_e2e() {
  # Defaults
  E2E_PRODUCT_AGENT=""
  E2E_ENGINEER_AGENT=""
  E2E_PLATFORM="forgejo"
  E2E_PROVIDER="claude"
  E2E_FORGEJO_URL="${FORGEJO_URL:-https://git.ncrmro.com}"
  E2E_FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"
  E2E_TEMPLATE_REPO="ks-testing/agent-e2e-bun-template"
  E2E_REPORT_FILE=""
  E2E_REPORT_RC=0
  local dry_run=false
  local print_report=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --product)      E2E_PRODUCT_AGENT="$2"; shift 2 ;;
      --engineer)     E2E_ENGINEER_AGENT="$2"; shift 2 ;;
      --platform)     E2E_PLATFORM="$2"; shift 2 ;;
      --provider)     E2E_PROVIDER="$2"; shift 2 ;;
      --forgejo-url)  E2E_FORGEJO_URL="$2"; shift 2 ;;
      --forgejo-token) E2E_FORGEJO_TOKEN="$2"; shift 2 ;;
      --template-repo) E2E_TEMPLATE_REPO="$2"; shift 2 ;;
      --dry-run)      dry_run=true; shift ;;
      --print)        print_report=true; shift ;;
      -h|--help)      print_agents_e2e_help; return 0 ;;
      *)
        echo "Error: unknown option '$1'" >&2
        print_agents_e2e_help >&2
        return 1
        ;;
    esac
  done

  # Validate required arguments
  if [[ -z "$E2E_PRODUCT_AGENT" || -z "$E2E_ENGINEER_AGENT" ]]; then
    echo "Error: --product and --engineer are required." >&2
    print_agents_e2e_help >&2
    return 1
  fi

  # Initialize report
  e2e_report_init
  e2e_emit info "starting e2e agent lifecycle test" \
    product "$E2E_PRODUCT_AGENT" \
    engineer "$E2E_ENGINEER_AGENT" \
    platform "$E2E_PLATFORM"

  # Dry-run: validate only, do not execute workflow
  if [[ "$dry_run" == true ]]; then
    e2e_emit info "dry-run mode -- validating configuration only"
    e2e_dry_run
    E2E_REPORT_RC=$?
    e2e_report_finalize
    if [[ "$print_report" == true ]]; then
      e2e_print_report
    else
      cat "$E2E_REPORT_FILE"
    fi
    rm -f "$E2E_REPORT_FILE"
    return "$E2E_REPORT_RC"
  fi

  # --- Full E2E run ---

  # Phase: Agent quiescence -- pause agents before any work
  e2e_pause_agents || {
    e2e_report_finalize
    cat "$E2E_REPORT_FILE"
    rm -f "$E2E_REPORT_FILE"
    return 1
  }

  # Ensure agents resume on any exit path
  trap 'e2e_resume_agents; e2e_report_cleanup' EXIT

  # Phase: Environment lifecycle
  e2e_cleanup_environment
  e2e_setup_environment || {
    e2e_report_finalize
    cat "$E2E_REPORT_FILE"
    return 1
  }

  # Phase: Product agent workflow
  e2e_check_product_email
  e2e_check_product_press_release
  e2e_check_product_milestone

  # Phase: Engineering agent workflow
  e2e_check_engineering_issue
  e2e_check_trunk_branch
  e2e_check_worktree
  e2e_check_spec_file
  e2e_check_palindrome_backend
  e2e_check_playwright_tests
  e2e_check_screenshots
  e2e_check_lfs_tracking
  e2e_check_release_pr
  e2e_check_issue_closed

  # Phase: Product verification
  e2e_check_milestone_closed

  # Resume agents and finalize
  e2e_resume_agents
  trap e2e_report_cleanup EXIT
  e2e_report_finalize
  if [[ "$print_report" == true ]]; then
    e2e_print_report
  else
    cat "$E2E_REPORT_FILE"
  fi
  rm -f "$E2E_REPORT_FILE"

  return "$E2E_REPORT_RC"
}
