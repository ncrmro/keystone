#!/usr/bin/env bash
# ks — Keystone infrastructure CLI
#
# Implements REQ-018: Keystone Home Directory and Repo Management
# See conventions/code.shell-scripts.md
#
# Usage: ks <command> [options]
#
# Commands:
#   approve --reason "<reason>" -- <command> [args...]  Run one allowlisted privileged command
#   build  [--lock] [HOSTS]                            Build home-manager profiles (or full system with --lock)
#   install [--force]                                   Launch the local installer workflow
#   update [--debug] [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy (unlocked current checkout with --dev, locked full system by default)
#   agents <pause|resume|status> <agent|all> [reason]  Pause or inspect agent task loops
#   docs   [topic|path]                                Browse keystone markdown docs with glow and fzf
#   photos search [options]                            Search Keystone Photos assets
#   sync-agent-assets                                 Refresh generated agent assets from the live profile manifest
#   grafana dashboards apply|export <uid>              Apply or export keystone dashboard JSON via Grafana API
#   sync-host-keys                                   Populate hostPublicKey in hosts.nix from live hosts
#   agent  [--local [MODEL]] [args...]               Launch AI agent with keystone OS context
#   doctor [--local [MODEL]] [args...]               Launch diagnostic AI agent with system state
#
# Host resolution:
#   1. If HOST is provided, use it directly
#   2. Otherwise, look up the current machine's hostname in hosts.nix
#
# HOSTS:
#   Comma-separated list of host names (e.g. host1,host2).
#   Defaults to current machine hostname.
#   Risky hosts should be placed last (e.g. workstation,ocean).
#
#
# Repo discovery:
#   1. $NIXOS_CONFIG_DIR if set and contains hosts.nix
#   2. Git repo root of current directory if it contains hosts.nix
#   3. ~/.keystone/repos/*/ if it contains hosts.nix
#   4. ~/nixos-config as fallback
#
# The --dev flag overrides keystone and agenix-secrets flake inputs with
# local clone paths for testing uncommitted changes.
#
# Requirements (RFC 2119)
#
# Repo management
#   MUST pull nixos-config, keystone, and agenix-secrets before building (lock mode).
#   MUST update flake.lock (nix flake update) before building, not after.
#   MUST commit and push flake.lock only after a successful build.
#   MUST verify managed lock repos are clean and on a branch before locking.
#   MUST automatically rebase managed lock repos when upstream has moved and there are no conflicts.
#   MUST push managed lock repos that are ahead of their upstream before locking.
#
# Build
#   MUST always use local .repos/keystone and .repos/agenix-secrets as --override-input
#     when those directories exist, regardless of --dev flag.
#   MUST build all target hosts before deploying any of them.
#   MUST pass --no-link to nix build to prevent ./result symlinks in the caller's CWD.
#   SHOULD build all targets in a single nix invocation (nix parallelises internally).
#   SHOULD hide warning lines during `ks update` by default; `--debug` MUST show them.
#
# Deployment
#   MUST deploy hosts sequentially (not in parallel) to limit blast radius.
#   MUST obtain sudo credentials before any other work (pull, lock, build) when a local
#     host is targeted, so the user is not interrupted mid-run.
#   SHOULD keep sudo credentials alive for the duration of the run.
#
# --dev mode
#   MUST skip pull, flake-update, commit, and push phases.
#   MAY be used with uncommitted local repo changes.

set -euo pipefail

# Clean up SSH ControlMaster sockets on exit
trap 'close_all_ssh_masters 2>/dev/null || true' EXIT

KS_DEBUG=false
KS_HM_USERS_FILTER=""
KS_HM_ALL_USERS=false
HM_ACTIVATION_RECORDS=()

ks_bool_true() {
  case "${1:-}" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

print_main_help() {
  cat <<'EOF'
Usage: ks <command> [options]

Build, deploy, and inspect Keystone-managed hosts.

Commands:
  help [command]                                    Show general or command-specific help
  approve --reason "<reason>" -- <command> [args...] Run one allowlisted privileged command
  build [--lock] [--user USERS] [--all-users] [HOSTS]
                                                    Build home-manager profiles, or full systems with --lock
  install [--force]                                  Launch the Keystone installer workflow
  update [--debug] [--dev] [--boot] [--pull] [--lock] [--user USERS] [--all-users] [HOSTS]
                                                    Pull, lock, build, push, and deploy
  agents <pause|resume|status|e2e> <agent|all> [options]
                                                    Control agent task-loop pause state or run E2E test
  docs [topic|path]                                 Browse Keystone docs with glow and fzf
  photos search [options]                           Search Keystone Photos assets
  sync-agent-assets                                 Refresh generated agent assets from the live profile manifest
  switch [--boot] [HOSTS]                           Deploy current state without pull, lock, or push
  sync-host-keys                                    Populate hostPublicKey in hosts.nix from live hosts
  grafana dashboards apply
  grafana dashboards export <uid>                   Apply or export Grafana dashboards
  print <file.md> [-o output.pdf] [--open]          Convert a markdown file to a print-ready PDF
  agent [--local [MODEL]] [args...]                 Launch an AI agent with Keystone context
  doctor [--local [MODEL]] [args...]                Launch a diagnostic AI agent with system state

HOSTS:
  Comma-separated host names such as workstation,ocean.
  Defaults to the current host resolved from hosts.nix.

Repo discovery:
  1. $NIXOS_CONFIG_DIR if it contains hosts.nix
  2. The current git repo root if it contains hosts.nix
  3. ~/.keystone/repos/*/ if it contains hosts.nix
  4. ~/nixos-config

Examples:
  ks build
  ks build --lock workstation,ocean
  ks update --dev
  ks docs
  ks docs desktop
  ks photos search --text "acme"
  ks agents pause all "waiting for human input"
  ks help grafana dashboards

Use "ks help <command>" for command-specific help.
EOF
}

print_approve_help() {
  cat <<'EOF'
Usage: ks approve --reason "<reason>" -- <command> [args...]

Request approval for one allowlisted privileged command.

Options:
  --reason TEXT         Human-readable reason shown before execution
  -h, --help            Show this help

Behavior:
  Uses desktop polkit approval when a graphical session is available.
  Falls back to a terminal sudo prompt when no graphical approval UI is available.
  Rejects commands that are not in the Keystone approval allowlist.

Examples:
  ks approve --reason "Enroll a hardware key for disk unlock." -- keystone-enroll-fido2 --auto
  ks approve --reason "Deploy the current local state." -- ks switch
EOF
}

print_build_help() {
  cat <<'EOF'
Usage: ks build [--lock] [--user USERS] [--all-users] [HOSTS]

Build Keystone configurations for one or more hosts.

Options:
  --lock               Build full NixOS system closures instead of home-manager profiles
  --user USERS         Limit home-manager builds to a comma-separated user list
  --all-users          Build all home-manager users on each target host
  -h, --help           Show this help

Defaults:
  Without --lock, ks builds home-manager activation packages only.
  Without HOSTS, ks resolves the current host from hosts.nix.

Examples:
  ks build
  ks build workstation,ocean
  ks build --user alice,agent-coder workstation
  ks build --lock ocean
EOF
}

print_update_help() {
  cat <<'EOF'
Usage: ks update [--debug] [--dev] [--boot] [--pull] [--lock] [--user USERS] [--all-users] [HOSTS]

Pull, verify, build, and deploy Keystone hosts.

Options:
  --debug              Show warnings from git and nix commands
  --dev                Build and deploy the current unlocked checkout without pull, lock, or push
  --boot               Register the new generation for next boot without switching now
  --pull               Pull managed repos only; skip build and deploy
  --lock               Force lock mode explicitly; this is the default unless --dev is set
  --user USERS         Limit home-manager activation to a comma-separated user list
  --all-users          Activate all home-manager users on each target host
  -h, --help           Show this help

Defaults:
  ks update runs in lock mode by default.
  HOSTS defaults to the current host resolved from hosts.nix.

Examples:
  ks update
  ks update --dev workstation
  ks update --boot ocean
  ks update --pull --dev
EOF
}

print_switch_help() {
  cat <<'EOF'
Usage: ks switch [--boot] [HOSTS]

Build and deploy the current local state without pull, lock, or push steps.

Options:
  --boot               Register the new generation for next boot without switching now
  -h, --help           Show this help

Defaults:
  HOSTS defaults to the current host resolved from hosts.nix.

Examples:
  ks switch
  ks switch workstation,ocean
  ks switch --boot ocean
EOF
}

print_install_help() {
  cat <<'EOF'
Usage: ks install [--force]

Launch the Keystone installer workflow on a booted installer environment.

Options:
  --force              Allow running even when /etc/NIXOS is not present
  -h, --help           Show this help

Behavior:
  Requires keystone-tui in PATH.
  Requires /etc/keystone/install-repo or /etc/keystone/install-config to be present.
  Re-execs the installer through non-interactive sudo on live media so
  disko and nixos-install run as root.
  Starts the installer flow, including explicit disk selection and confirmation
  before destructive disko operations.

Examples:
  ks install
  ks install --force
EOF
}

print_sync_host_keys_help() {
  cat <<'EOF'
Usage: ks sync-host-keys

Fetch SSH host public keys from live hosts and write them into hosts.nix.

Options:
  -h, --help           Show this help

Behavior:
  Hosts without sshTarget are skipped.
  When sshTarget is unreachable and fallbackIP exists, ks retries over fallbackIP.

Examples:
  ks sync-host-keys
EOF
}

print_sync_agent_assets_help() {
  cat <<'EOF'
Usage: ks sync-agent-assets

Refresh generated Keystone agent assets for the current user from the current
profile manifest.

Options:
  -h, --help           Show this help

Behavior:
  Rewrites generated instruction files, curated command files, and managed
  Codex skills from the live keystone checkout in development mode.

Examples:
  ks sync-agent-assets
EOF
}

print_agent_help() {
  cat <<'EOF'
Usage: ks agent [--local [MODEL]] [args...]

Launch an AI coding agent with Keystone conventions and host context.

Options:
  --local [MODEL]      Use the local Ollama-backed model, or the configured default model
  -h, --help           Show this help

Behavior:
  Any remaining args are passed through to the underlying claude invocation.

Examples:
  ks agent
  ks agent --local
  ks agent --local qwen2.5-coder:14b --continue
EOF
}

print_doctor_help() {
  cat <<'EOF'
Usage: ks doctor [--full] [--local [MODEL]] [args...]

Generate the scripted fleet doctor report, then optionally launch the default agent.

Options:
  --full               Also run the E2E agent lifecycle test (ks agents e2e) after the report
  --local [MODEL]      If you choose to launch the agent, use the local Ollama-backed model
  -h, --help           Show this help

Behavior:
  Prints the fleet report to stdout.
  With --full, additionally runs the E2E agent product lifecycle test (REQ-031).
  In an interactive terminal, ks then asks whether to launch the default agent.
  Any remaining args are passed through to the agent if you choose to launch it.

Examples:
  ks doctor
  ks doctor --full
  ks doctor --local
  ks doctor --local mistral --continue
EOF
}

print_agents_help() {
  cat <<'EOF'
Usage: ks agents <subcommand> <agent|all> [options]

Control autonomous agent task loops and run agent integration tests.

Subcommands:
  pause               Create the paused marker so scheduled task-loop runs no-op
  resume              Remove the paused marker and allow task-loop runs again
  status              Show whether the target agent task loop is paused
  e2e                 Run the end-to-end agent product lifecycle test (REQ-031)

Arguments:
  <agent|all>         One configured agent name, or "all" for every configured agent
  [reason]            Optional pause reason stored with the marker

Examples:
  ks agents pause drago "waiting for review feedback"
  ks agents pause all "human focus block"
  ks agents status luce
  ks agents resume all
  ks agents e2e --product luce --engineer drago
EOF
}

print_docs_help() {
  cat <<'EOF'
Usage: ks docs [topic|path]

Browse Keystone Markdown docs in the terminal with glow and fzf.

Arguments:
  [topic|path]          Optional doc topic or relative docs path

Topics:
  os                    Open the Keystone OS entry page
  terminal              Open the terminal module entry page
  desktop               Open the desktop entry page
  agents                Open the agents entry page
  projects              Open the projects entry page

Options:
  -h, --help            Show this help

Behavior:
  With no argument, ks opens an fzf picker over Markdown files under docs/ only.
  Type to filter, press Enter to open, and press Esc to cancel.
  A relative docs path such as terminal/projects.md also works.

Examples:
  ks docs
  ks docs os
  ks docs terminal/projects.md
EOF
}

print_photos_help() {
  cat <<'EOF'
Usage: ks photos search [options]

Search Immich assets through Keystone's photo CLI.

Subcommands:
  search               Run a metadata and smart search against Immich
  people               List known Immich people

Options:
  --text QUERY         Generic smart-search query text
  --context QUERY      Additional contextual search text
  --ocr QUERY          OCR-focused search text
  --person NAME        Restrict results to an Immich person name (repeatable)
  --album NAME         Restrict results to an Immich album name (repeatable)
  --tag NAME           Restrict results to an Immich tag value (repeatable)
  --country NAME       Restrict results to a country
  --state NAME         Restrict results to a state or province
  --city NAME          Restrict results to a city
  --camera-make NAME   Restrict results to a camera make
  --camera-model NAME  Restrict results to a camera model
  --lens-model NAME    Restrict results to a lens model
  --filename TEXT      Restrict results to filenames containing TEXT
  --description TEXT   Restrict results to descriptions containing TEXT
  --type TYPE          Asset type: photo, screenshot, image, or video
  --kind KIND          Search preset; supported: business-card
  --from YYYY-MM-DD    Inclusive takenAfter date
  --to YYYY-MM-DD      Inclusive takenBefore date
  --start-date YYYY-MM-DD
                        Alias for --from
  --end-date YYYY-MM-DD
                        Alias for --to
  --limit N            Max results to request (default: 20)
  --json               Emit structured JSON
  -h, --help           Show this help

Examples:
  ks photos search --text "acme"
  ks photos search --album "Screenshots - alice" --tag "receipt" --city "Austin"
  ks photos search --text "nick romero" --kind business-card
  ks photos search --person "Nick Romero" --type photo
  ks photos people --json
  ks photos search --text "ks build" --type screenshot --from 2026-01-01 --to 2026-03-31
EOF
}

print_print_help() {
  cat <<'EOF'
Usage: ks print <file.md> [-o output.pdf] [--open] [--preview]

Convert a markdown file to a print-ready PDF using Keystone's compact print stylesheet.

Arguments:
  <file.md>            Path to the markdown input file (required)

Options:
  -o, --output PATH    Output PDF path (default: same as input with .pdf extension)
  --open               Open the PDF in the system viewer after generation
  --no-print           Generate the PDF only; do not send to the default printer
  --preview            Generate the PDF, open it, and skip auto-printing
  -h, --help           Show this help

Engine selection (first available wins):
  weasyprint           HTML-based renderer — clean, CSS-driven typography
  wkhtmltopdf          WebKit-based renderer — fallback
  pdflatex             LaTeX-based renderer — fallback
  xelatex              LaTeX-based renderer — fallback

Examples:
  ks print ~/Downloads/garden-guide.md
  ks print report.md -o ~/Desktop/report.pdf --open
  ks print report.md --preview
  ks print tests/fixtures/portfolio-review-print-demo.md --preview
  ks print instructions.md -o /tmp/instructions.pdf
EOF
}

print_grafana_help() {
  cat <<'EOF'
Usage: ks grafana dashboards <apply|export> [uid]

Manage checked-in Keystone Grafana dashboards through the Grafana API.

Subcommands:
  dashboards apply     Apply every dashboard JSON file in the repo
  dashboards export <uid>
                       Export one dashboard by UID into its checked-in JSON file

Options:
  -h, --help           Show this help

Examples:
  ks grafana dashboards apply
  ks grafana dashboards export keystone-host-overview
EOF
}

print_grafana_dashboards_help() {
  cat <<'EOF'
Usage: ks grafana dashboards <apply|export> [uid]

Apply or export Keystone Grafana dashboards.

Subcommands:
  apply                Push all checked-in dashboard JSON files to Grafana
  export <uid>         Pull one dashboard by UID into its checked-in JSON file

Environment:
  GRAFANA_URL          Override the Grafana base URL
  GRAFANA_API_KEY      Override the Grafana API key

Examples:
  ks grafana dashboards apply
  ks grafana dashboards export keystone-system-index
EOF
}

show_help_topic() {
  case "${1:-}" in
    ""|ks)
      print_main_help
      ;;
    approve)
      print_approve_help
      ;;
    build)
      print_build_help
      ;;
    update)
      print_update_help
      ;;
    switch)
      print_switch_help
      ;;
    install)
      print_install_help
      ;;
    sync-agent-assets)
      print_sync_agent_assets_help
      ;;
    agents)
      print_agents_help
      ;;
    docs)
      print_docs_help
      ;;
    photos)
      print_photos_help
      ;;
    sync-host-keys)
      print_sync_host_keys_help
      ;;
    agent)
      print_agent_help
      ;;
    doctor)
      print_doctor_help
      ;;
    print)
      print_print_help
      ;;
    grafana)
      if [[ "${2:-}" == "dashboards" ]]; then
        print_grafana_dashboards_help
      else
        print_grafana_help
      fi
      ;;
    *)
      echo "Error: Unknown help topic '$*'" >&2
      echo "Run 'ks --help' to see available commands." >&2
      return 1
      ;;
  esac
}

is_root_user() {
  [[ ${EUID:-$(id -u)} -eq 0 ]]
}

has_graphical_session() {
  [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]
}

resolve_approval_helper() {
  if command -v keystone-approve-exec >/dev/null 2>&1; then
    command -v keystone-approve-exec
    return 0
  fi

  if [[ -x /run/current-system/sw/bin/keystone-approve-exec ]]; then
    printf '%s\n' /run/current-system/sw/bin/keystone-approve-exec
    return 0
  fi

  echo "Error: keystone-approve-exec is not available in PATH." >&2
  echo "Enable keystone.security.privilegedApproval on this host first." >&2
  return 1
}

run_root_command() {
  if is_root_user; then
    "$@"
  else
    sudo "$@"
  fi
}

cmd_approve() {
  local reason=""
  local requested_argv=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_approve_help
        return 0
        ;;
      --reason)
        [[ $# -lt 2 ]] && { echo "Error: --reason requires a value" >&2; return 1; }
        reason="$2"
        shift 2
        ;;
      --)
        shift
        requested_argv=("$@")
        break
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        print_approve_help >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$reason" ]]; then
    echo "Error: --reason is required." >&2
    print_approve_help >&2
    return 1
  fi

  if [[ ${#requested_argv[@]} -eq 0 ]]; then
    echo "Error: Missing command after --." >&2
    print_approve_help >&2
    return 1
  fi

  local approval_helper
  approval_helper=$(resolve_approval_helper) || return 1

  local matched_entry
  if ! matched_entry=$("$approval_helper" --validate --reason "$reason" -- "${requested_argv[@]}"); then
    return 1
  fi

  local display_name policy_reason
  display_name=$(echo "$matched_entry" | jq -r '.displayName')
  policy_reason=$(echo "$matched_entry" | jq -r '.reason')

  echo "Approval request: $display_name"
  echo "Requested reason: $reason"
  echo "Policy reason: $policy_reason"

  if is_root_user || [[ -n "${KS_APPROVE_EXECUTING:-}" ]]; then
    exec "$approval_helper" --reason "$reason" -- "${requested_argv[@]}"
  fi

  if has_graphical_session && command -v pkexec >/dev/null 2>&1; then
    exec pkexec "$approval_helper" --reason "$reason" -- "${requested_argv[@]}"
  fi

  exec sudo "$approval_helper" --reason "$reason" -- "${requested_argv[@]}"
}

run_with_warning_filter() {
  if [[ "${KS_DEBUG}" == true ]]; then
    "$@"
  else
    "$@" 2> >(
      awk '
        /^warning:/ { next }
        /^evaluation warning:/ { next }
        { print > "/dev/stderr" }
      '
    )
  fi
}

cmd_sync_agent_assets() {
  if ! command -v keystone-sync-agent-assets >/dev/null 2>&1; then
    echo "Error: keystone-sync-agent-assets is not available in PATH." >&2
    echo "Refresh the home-manager profile before using this command." >&2
    return 1
  fi

  keystone-sync-agent-assets "$@"
}

known_agents_list() {
  if ! command -v agentctl >/dev/null 2>&1; then
    echo "Error: agentctl is not available in PATH." >&2
    return 1
  fi

  local known_agents
  known_agents=$(agentctl 2>&1 | sed -n 's/^Known agents: //p' | head -n1)
  if [[ -z "$known_agents" ]]; then
    echo "Error: could not discover configured agents from agentctl." >&2
    return 1
  fi

  printf '%s\n' "$known_agents" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sed '/^$/d'
}

safe_systemctl_state() {
  local agent="$1"
  local unit="$2"
  local state

  state=$(agentctl "$agent" is-active "$unit" 2>/dev/null | head -n1 | tr -d '\r')
  if [[ -n "$state" ]]; then
    printf '%s\n' "$state"
  else
    printf '%s\n' "unknown"
  fi
}

count_status_matches() {
  local yaml="$1"
  local status="$2"
  local count

  count=$(printf '%s\n' "$yaml" | grep -c "status: ${status}" 2>/dev/null || true)
  printf '%s\n' "${count:-0}"
}

failed_units_list() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi

  systemctl --failed --plain --no-legend --no-pager 2>/dev/null \
    | sed -E 's/^[[:space:]]*●?[[:space:]]+//; s/[[:space:]].*$//' \
    | sed '/^$/d' || true
}

doctor_progress() {
  if [[ -t 2 ]]; then
    printf 'ks doctor: %s\n' "$1" >&2
  fi
}

# E2E agent test harness (REQ-031) -- delegates to the agents-e2e TypeScript package.
# @KS_AGENTS_E2E@ is replaced at Nix build time with the store path of the binary.
_ks_agents_e2e_bin="@KS_AGENTS_E2E@"
cmd_agents_e2e() {
  if [[ -x "$_ks_agents_e2e_bin" ]]; then
    "$_ks_agents_e2e_bin" "$@"
  else
    echo "Error: agents-e2e binary not found at $_ks_agents_e2e_bin" >&2
    echo "Run from the agents-e2e package devshell: bun run src/main.ts" >&2
    return 1
  fi
}

resolve_agent_targets() {
  local target="$1"

  if [[ "$target" == "all" ]]; then
    known_agents_list
    return
  fi

  if known_agents_list | grep -Fxq "$target"; then
    printf '%s\n' "$target"
    return
  fi

  echo "Error: unknown agent '$target'." >&2
  echo "Run 'agentctl' to see configured agents." >&2
  return 1
}

cmd_agents() {
  if [[ $# -lt 1 ]]; then
    print_agents_help >&2
    return 1
  fi

  local action="$1"
  shift

  # Subcommands that handle their own argument parsing
  case "$action" in
    e2e) cmd_agents_e2e "$@"; return $? ;;
    -h|--help) print_agents_help; return 0 ;;
  esac

  # Subcommands that require a target agent
  if [[ $# -lt 1 ]]; then
    print_agents_help >&2
    return 1
  fi

  local target="$1"
  shift

  case "$action" in
    pause|resume|status) ;;
    *)
      echo "Error: unknown agents subcommand '$action'." >&2
      print_agents_help >&2
      return 1
      ;;
  esac

  mapfile -t targets < <(resolve_agent_targets "$target") || return 1

  local rc=0
  local agent
  for agent in "${targets[@]}"; do
    case "$action" in
      pause)
        if ! agentctl "$agent" pause "$@"; then
          rc=1
        fi
        ;;
      resume)
        if ! agentctl "$agent" resume; then
          rc=1
        fi
        ;;
      status)
        if ! agentctl "$agent" paused; then
          rc=1
        fi
        ;;
    esac
  done

  return "$rc"
}

resolve_keystone_docs_root() {
  local current_repo=""
  current_repo=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$current_repo" && -f "$current_repo/docs/ks.md" && -f "$current_repo/packages/ks/ks.sh" ]]; then
    printf '%s\n' "$current_repo"
    return 0
  fi

  local configured_repo="${HOME}/.keystone/repos/ncrmro/keystone"
  if [[ -f "$configured_repo/docs/ks.md" && -f "$configured_repo/packages/ks/ks.sh" ]]; then
    printf '%s\n' "$configured_repo"
    return 0
  fi

  local repo_root=""
  repo_root=$(find_repo 2>/dev/null || true)
  if [[ -n "$repo_root" ]]; then
    if [[ -f "$repo_root/.repos/keystone/docs/ks.md" && -f "$repo_root/.repos/keystone/packages/ks/ks.sh" ]]; then
      printf '%s\n' "$repo_root/.repos/keystone"
      return 0
    fi

    if [[ -f "$repo_root/keystone/docs/ks.md" && -f "$repo_root/keystone/packages/ks/ks.sh" ]]; then
      printf '%s\n' "$repo_root/keystone"
      return 0
    fi
  fi

  echo "Error: could not find a local keystone checkout with a docs/ directory." >&2
  echo "Expected one of:" >&2
  echo "  - current repo root" >&2
  echo "  - ~/.keystone/repos/ncrmro/keystone" >&2
  echo "  - <nixos-config>/.repos/keystone" >&2
  return 1
}

resolve_docs_target() {
  local docs_root="$1"
  local query="${2:-}"

  case "$query" in
    "" )
      return 1
      ;;
    os)
      printf '%s\n' "$docs_root/os/installation.md"
      return 0
      ;;
    terminal)
      printf '%s\n' "$docs_root/terminal/terminal.md"
      return 0
      ;;
    desktop)
      printf '%s\n' "$docs_root/desktop.md"
      return 0
      ;;
    agents)
      printf '%s\n' "$docs_root/agents/agents.md"
      return 0
      ;;
    projects)
      printf '%s\n' "$docs_root/terminal/projects.md"
      return 0
      ;;
  esac

  if [[ -f "$docs_root/$query" ]]; then
    printf '%s\n' "$docs_root/$query"
    return 0
  fi

  if [[ -f "$docs_root/$query.md" ]]; then
    printf '%s\n' "$docs_root/$query.md"
    return 0
  fi

  echo "Error: unknown docs topic or path '$query'." >&2
  echo "Try: ks docs" >&2
  return 1
}

cmd_docs() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_docs_help
    return 0
  fi

  local repo_root docs_root target
  repo_root=$(resolve_keystone_docs_root) || return 1
  docs_root="$repo_root/docs"

  if [[ $# -gt 0 ]]; then
    target=$(resolve_docs_target "$docs_root" "$1") || return 1
    glow "$target"
    return 0
  fi

  printf '%s\n' "Filter docs with text" >&2
  printf '%s\n' "Enter: open in glow" >&2
  printf '%s\n' "Esc: cancel" >&2

  local theme_dir waybar_css fzf_colors theme_bg theme_fg theme_accent
  theme_dir="${XDG_CONFIG_HOME:-$HOME/.config}/keystone/current/theme"
  waybar_css="$theme_dir/waybar.css"
  theme_bg="#00120c"
  theme_fg="#b6bfbc"
  theme_accent="#b8a26c"

  if [[ -f "$waybar_css" ]]; then
    theme_bg="$(sed -n 's/^@define-color background \([^;]*\);/\1/p' "$waybar_css" | head -n1)"
    theme_fg="$(sed -n 's/^@define-color foreground \([^;]*\);/\1/p' "$waybar_css" | head -n1)"
    theme_accent="$(sed -n 's/^@define-color gold \([^;]*\);/\1/p' "$waybar_css" | head -n1)"
    [[ -n "$theme_bg" ]] || theme_bg="#00120c"
    [[ -n "$theme_fg" ]] || theme_fg="#b6bfbc"
    [[ -n "$theme_accent" ]] || theme_accent="#b8a26c"
  fi

  fzf_colors="bg:${theme_bg},bg+:${theme_bg},fg:${theme_fg},fg+:${theme_fg},hl:${theme_accent},hl+:${theme_accent},border:${theme_accent},label:${theme_accent},prompt:${theme_accent},pointer:${theme_accent},info:${theme_fg},gutter:${theme_bg},separator:${theme_accent},scrollbar:${theme_accent}"

  target="$(
    find "$docs_root" -type f -name '*.md' \
      ! -path "$docs_root/.jekyll-cache/*" \
      | sed "s|^$docs_root/||" \
      | sort \
      | fzf \
          --style=full \
          --layout=reverse \
          --border=rounded \
          --border-label=' Keystone docs ' \
          --input-label=' Filter ' \
          --list-label=' Files ' \
          --info=inline-right \
          --color="$fzf_colors" \
          --prompt='Keystone docs > '
  )"

  [[ -n "$target" ]] || return 0
  glow "$docs_root/$target"
}

cmd_photos() {
  if [[ $# -eq 0 ]]; then
    print_photos_help
    return 0
  fi

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_photos_help
    return 0
  fi

  if ! command -v keystone-photos >/dev/null 2>&1; then
    echo "Error: keystone-photos is not available in PATH." >&2
    echo "Refresh the home-manager profile before using this command." >&2
    return 1
  fi

  keystone-photos "$@"
}

# --- Discover repo root ---
# All paths are resolved with readlink -f because Nix `path:` flake URIs
# break on symlinks (e.g. ~/nixos-config -> .repos/ncrmro/nixos-config).
find_repo() {
  if [[ -n "${NIXOS_CONFIG_DIR:-}" ]] && [[ -f "$NIXOS_CONFIG_DIR/hosts.nix" ]]; then
    readlink -f "$NIXOS_CONFIG_DIR"
    return
  fi

  local dir
  dir=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$dir" ]] && [[ -f "$dir/hosts.nix" ]]; then
    readlink -f "$dir"
    return
  fi

  # Scan for any repo with hosts.nix in ~/.keystone/repos/
  if [[ -d "$HOME/.keystone/repos" ]]; then
    local match
    match=$(find "$HOME/.keystone/repos" -maxdepth 3 -name hosts.nix -print -quit)
    if [[ -n "$match" ]]; then
      readlink -f "$(dirname "$match")"
      return
    fi
  fi

  if [[ -f "$HOME/nixos-config/hosts.nix" ]]; then
    readlink -f "$HOME/nixos-config"
    return
  fi

  echo "Error: Cannot find nixos-config repo (no hosts.nix found)." >&2
  echo "Set NIXOS_CONFIG_DIR or run from within the repo." >&2
  exit 1
}

# --- Get repo registry from repos.nix ---
get_repos_registry() {
  local repo_root="$1"
  if [[ -f "$repo_root/repos.nix" ]]; then
    nix eval -f "$repo_root/repos.nix" --json 2>/dev/null
  else
    echo "{}"
  fi
}

# --- Resolve sshTarget, deriving from hostname + headscaleDomain if missing ---
resolve_ssh_target() {
  local repo_root="$1" host="$2" host_json="$3"
  local target
  target=$(echo "$host_json" | jq -r '.sshTarget // empty')
  if [[ -n "$target" ]]; then
    echo "$target"
    return
  fi
  # Derive from hostname + headscaleDomain (mirrors modules/hosts.nix default)
  local hostname hs_domain
  hostname=$(echo "$host_json" | jq -r '.hostname')
  hs_domain=$(nix eval "$repo_root#nixosConfigurations.$host.config.keystone.headscaleDomain" --raw 2>/dev/null || true)
  if [[ -n "$hs_domain" ]]; then
    echo "${hostname}.${hs_domain}"
  fi
}

# --- SSH ControlMaster for hardware-key hosts ---
# Opens a persistent SSH connection so YubiKey touch is only needed once per
# host per deploy session. All subsequent ssh/nix-copy commands reuse it.

KS_SSH_CONTROL_DIR=""

_ssh_control_path() {
  local target="$1"
  echo "${KS_SSH_CONTROL_DIR}/ks-%r@%h:%p"
}

open_ssh_master() {
  local target="$1"
  if [[ -z "$KS_SSH_CONTROL_DIR" ]]; then
    KS_SSH_CONTROL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ks-ssh.XXXXXX")
  fi
  local ctl
  ctl=$(_ssh_control_path "$target")
  # Only open if not already connected
  if ! ssh -o ControlPath="$ctl" -O check "root@${target}" 2>/dev/null; then
    echo "Establishing SSH connection to root@${target} (hardware key touch may be required)..."
    ssh -o ControlMaster=yes -o ControlPath="$ctl" -o ControlPersist=600 \
        -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=30 \
        -fN "root@${target}"
  fi
}

close_ssh_master() {
  local target="$1"
  local ctl
  ctl=$(_ssh_control_path "$target")
  ssh -o ControlPath="$ctl" -O exit "root@${target}" 2>/dev/null || true
}

close_all_ssh_masters() {
  if [[ -n "$KS_SSH_CONTROL_DIR" && -d "$KS_SSH_CONTROL_DIR" ]]; then
    for sock in "$KS_SSH_CONTROL_DIR"/ks-*; do
      [[ -e "$sock" ]] && ssh -o ControlPath="$sock" -O exit "" 2>/dev/null || true
    done
    rm -rf "$KS_SSH_CONTROL_DIR"
    KS_SSH_CONTROL_DIR=""
  fi
}

# SSH wrapper that uses ControlMaster when available
ks_ssh() {
  local target="$1"; shift
  local ctl
  ctl=$(_ssh_control_path "$target")
  if [[ -n "$KS_SSH_CONTROL_DIR" ]] && ssh -o ControlPath="$ctl" -O check "root@${target}" 2>/dev/null; then
    ssh -o ControlPath="$ctl" "root@${target}" "$@"
  else
    ssh "root@${target}" "$@"
  fi
}

# nix copy wrapper that routes through ControlMaster
ks_nix_copy() {
  local target="$1"; shift
  local ctl
  ctl=$(_ssh_control_path "$target")
  if [[ -n "$KS_SSH_CONTROL_DIR" ]] && ssh -o ControlPath="$ctl" -O check "root@${target}" 2>/dev/null; then
    NIX_SSHOPTS="-o ControlPath=$ctl" nix copy --to "ssh://root@${target}" "$@"
  else
    nix copy --to "ssh://root@${target}" "$@"
  fi
}

# Test SSH connectivity, preferring ControlMaster
ks_ssh_test() {
  local target="$1"
  local ctl
  ctl=$(_ssh_control_path "$target")
  if [[ -n "$KS_SSH_CONTROL_DIR" ]] && ssh -o ControlPath="$ctl" -O check "root@${target}" 2>/dev/null; then
    return 0
  fi
  ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${target}" true 2>/dev/null
}

# --- Resolve HOST from hosts.nix ---
resolve_host() {
  local hosts_nix="$1"
  local host="${2:-}"

  if [[ -z "$host" ]]; then
    local current
    current=$(hostname)
    host=$(nix eval -f "$hosts_nix" --raw \
      --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m")
    if [[ -z "$host" ]]; then
      echo "Error: No hosts.nix entry with hostname '$current'." >&2
      echo "Specify HOST explicitly: ks <command> <HOST>" >&2
      exit 1
    fi
  fi

  # Validate HOST exists
  if ! nix eval -f "$hosts_nix" "$host" --json >/dev/null 2>&1; then
    echo "Error: Unknown host '$host'." >&2
    echo "Known hosts:" >&2
    nix eval -f "$hosts_nix" --apply 'h: builtins.concatStringsSep "\n  " (builtins.attrNames h)' --raw >&2
    echo >&2
    exit 1
  fi

  echo "$host"
}

# --- Local override args (always applied when local repos exist) ---
# Returns --override-input flags for any local repos found.
# Silent and exits cleanly if no local repos are present.
local_override_args() {
  local repo_root="$1"
  local args=()
  local registry
  registry=$(get_repos_registry "$repo_root")

  # Parse registry entries
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key input path
    key=$(echo "$line" | cut -d'|' -f1)
    input=$(echo "$line" | cut -d'|' -f2)

    # Check for checkout in standard locations:
    # 1. ~/.keystone/repos/{key}
    # 2. $repo_root/.repos/{name}
    # 3. $repo_root/.submodules/{name} (legacy)
    # 4. $repo_root/{name} (legacy)
    local name="${key##*/}"
    path=""
    if [[ -d "$HOME/.keystone/repos/$key" ]]; then
      path="$HOME/.keystone/repos/$key"
    elif [[ -d "$repo_root/.repos/$name" ]]; then
      path="$repo_root/.repos/$name"
    elif [[ -d "$repo_root/.submodules/$name" ]]; then
      path="$repo_root/.submodules/$name"
    elif [[ -d "$repo_root/$name" ]]; then
      path="$repo_root/$name"
    fi

    if [[ -n "$path" && "$input" != "null" ]]; then
      args+=(--override-input "$input" "path:$path")
    fi
  done <<< "$(echo "$registry" | jq -r 'to_entries[] | "\(.key)|\(.value.flakeInput)"')"

  echo "${args[@]}"   # empty string if no repos found — no error, no exit
}

resolve_current_hm_user() {
  local repo_root="$1"
  local host="$2"
  if [[ -z "$host" ]]; then
    echo ""
    return
  fi
  local preferred_user="${SUDO_USER:-${USER:-$(id -un)}}"
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"
  local users_json
  users_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${host}.config.home-manager.users" \
    --apply 'builtins.attrNames' --json \
    "${override_args[@]}" 2>/dev/null || echo "[]")

  if echo "$users_json" | jq -e --arg user "$preferred_user" '.[] | select(. == $user)' >/dev/null 2>&1; then
    echo "$preferred_user"
    return
  fi

  local fallback_user
  fallback_user=$(echo "$users_json" | jq -r 'map(select(startswith("agent-") | not)) | .[0] // ""')
  if [[ -n "$fallback_user" ]]; then
    echo "$fallback_user"
    return
  fi

  echo "$users_json" | jq -r '.[0] // ""'
}

eval_hm_user_attr_json() {
  local repo_root="$1"
  local host="$2"
  local user="$3"
  local attr_suffix="$4"
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${host}.config.home-manager.users.\"${user}\".${attr_suffix}" \
    --json \
    "${override_args[@]}" 2>/dev/null
}

resolve_ollama_user() {
  local repo_root="$1"
  local host="$2"
  local user="${3:-}"

  if [[ -n "$user" ]]; then
    echo "$user"
    return
  fi

  local resolved_user
  resolved_user=$(resolve_current_hm_user "$repo_root" "$host")
  if [[ -z "$resolved_user" ]]; then
    echo "Error: could not resolve a home-manager user for host '$host'." >&2
    exit 1
  fi

  echo "$resolved_user"
}

resolve_ollama_enabled() {
  local repo_root="$1"
  local host="$2"
  local user
  user=$(resolve_ollama_user "$repo_root" "$host" "${3:-}")

  eval_hm_user_attr_json "$repo_root" "$host" "$user" "keystone.terminal.ai.ollama.enable" \
    | jq -r 'if . == true then "true" else "false" end' 2>/dev/null || echo "false"
}

resolve_ollama_host() {
  local repo_root="$1"
  local host="$2"
  local user
  user=$(resolve_ollama_user "$repo_root" "$host" "${3:-}")

  eval_hm_user_attr_json "$repo_root" "$host" "$user" "keystone.terminal.ai.ollama.host" \
    | jq -r '. // ""' 2>/dev/null
}

resolve_ollama_default_model() {
  local repo_root="$1"
  local host="$2"
  local user
  user=$(resolve_ollama_user "$repo_root" "$host" "${3:-}")

  eval_hm_user_attr_json "$repo_root" "$host" "$user" "keystone.terminal.ai.ollama.defaultModel" \
    | jq -r '. // ""' 2>/dev/null
}

require_ollama_enabled() {
  local repo_root="$1"
  local host="$2"
  local user="$3"
  local enabled
  enabled=$(resolve_ollama_enabled "$repo_root" "$host" "$user")
  if [[ "$enabled" != "true" ]]; then
    echo "Error: local model support is not enabled for home-manager user '$user' on host '$host'." >&2
    echo "Set keystone.terminal.ai.ollama.enable = true to use --local." >&2
    exit 1
  fi
}

resolve_local_model() {
  local explicit_model="$1"
  local default_model="$2"

  if [[ -n "$explicit_model" && "$explicit_model" != "default" ]]; then
    echo "$explicit_model"
    return
  fi

  if [[ -n "$default_model" ]]; then
    echo "$default_model"
    return
  fi

  echo "Error: no local model was provided and keystone.terminal.ai.ollama.defaultModel is not set." >&2
  exit 1
}

list_ollama_models() {
  local ollama_host="$1"

  if [[ -z "$ollama_host" ]]; then
    echo "  - _API endpoint not configured_"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "  - _curl not installed_"
    return
  fi

  local response_file
  response_file=$(mktemp "${TMPDIR:-/tmp}/ollama-tags.XXXXXX.json")

  local http_code="000"
  http_code=$(curl -sS -o "$response_file" -w '%{http_code}' \
    --connect-timeout 2 \
    --max-time 5 \
    "${ollama_host%/}/api/tags" 2>/dev/null || echo "000")

  if [[ "$http_code" != "200" ]]; then
    rm -f "$response_file"
    echo "  - _API unreachable_"
    return
  fi

  local models
  models=$(jq -r '.models[]?.name // empty' "$response_file" 2>/dev/null || true)
  rm -f "$response_file"

  if [[ -z "$models" ]]; then
    echo "  - _No models found_"
    return
  fi

  while IFS= read -r model; do
    [[ -n "$model" ]] && echo "  - $model"
  done <<< "$models"
}

# --- Push keystone with fork fallback (REQ-016.9) ---
# Pushes the local keystone repo. If the user lacks push access to the upstream
# repo, forks it and pushes to the fork instead.
push_keystone_with_fork_fallback() {
  local ks_path="$1"
  [[ -z "$ks_path" || ! -d "$ks_path" ]] && return 0

  # Extract owner/repo from remote URL (handles SSH, HTTPS, and Forgejo SSH)
  local remote_url
  remote_url=$(git -C "$ks_path" remote get-url origin 2>/dev/null) || return 1
  local _tmp _repo _rest _owner owner_repo
  _tmp="${remote_url##*[:/]}"     # last path segment: "keystone.git"
  _repo="${_tmp%.git}"            # strip .git suffix
  _rest="${remote_url%"$_tmp"}"   # everything before last segment
  _rest="${_rest%[:/]}"           # strip trailing : or /
  _owner="${_rest##*[:/]}"        # owner segment
  owner_repo="${_owner}/${_repo}"

  if ! command -v gh >/dev/null 2>&1; then
    echo "Warning: gh CLI not found. Attempting direct push..." >&2
    run_with_warning_filter git -C "$ks_path" push || {
      echo "Error: Push failed. Install gh CLI for fork-fallback support." >&2
      return 1
    }
    return 0
  fi

  # Check collaborator permission
  local current_user permission
  current_user=$(gh api user -q .login 2>/dev/null) || current_user=""
  if [[ -n "$current_user" ]]; then
    permission=$(gh api "repos/$owner_repo/collaborators/$current_user/permission" -q '.permission' 2>/dev/null) || permission="none"
  else
    permission="none"
  fi

  case "$permission" in
    admin|maintain|write)
      echo "Pushing keystone (direct access)..."
      run_with_warning_filter git -C "$ks_path" push
      ;;
    *)
      echo "No push access to $owner_repo, pushing to fork..."
      # Ensure fork exists
      gh repo fork "$owner_repo" --clone=false 2>/dev/null || true
      local fork_remote
      local repo_name
      repo_name=$(basename "$owner_repo")
      repo_name="${repo_name%.git}"
      fork_remote="git@github.com:$current_user/${repo_name}.git"
      # Set origin to fork for this push (will be restored by user if needed)
      git -C "$ks_path" remote set-url origin "$fork_remote"
      run_with_warning_filter git -C "$ks_path" push -u origin "$(git -C "$ks_path" branch --show-current)"
      echo "Pushed to fork: $fork_remote"
      ;;
  esac
}

# --- List home-manager users for a host (REQ-016.3) ---
# Evaluates the flake to get all home-manager managed usernames for a host.
list_hm_users() {
  local repo_root="$1" host="$2"
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"
  timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${host}.config.home-manager.users" \
    --apply 'builtins.attrNames' --json \
    "${override_args[@]}" 2>/dev/null | jq -r '.[]'
}

list_target_hm_users() {
  local repo_root="$1"
  local host="$2"
  local users
  users=$(list_hm_users "$repo_root" "$host") || return 1
  [[ -z "$users" ]] && return 0

  if [[ -n "$KS_HM_USERS_FILTER" ]]; then
    local matched=()
    local requested=()
    IFS=',' read -ra requested <<< "$KS_HM_USERS_FILTER"
    for requested_user in "${requested[@]}"; do
      local found=false
      while IFS= read -r available_user; do
        [[ -z "$available_user" ]] && continue
        if [[ "$available_user" == "$requested_user" ]]; then
          matched+=("$available_user")
          found=true
          break
        fi
      done <<< "$users"

      if [[ "$found" == false ]]; then
        echo "Error: home-manager user '$requested_user' is not configured on host '$host'." >&2
        return 1
      fi
    done

    printf '%s\n' "${matched[@]}"
    return 0
  fi

  if [[ "$KS_HM_ALL_USERS" == true ]]; then
    printf '%s\n' "$users"
    return 0
  fi

  local current_hostname host_hostname
  current_hostname=$(hostname)
  host_hostname=$(nix eval -f "$repo_root/hosts.nix" "$host.hostname" --raw 2>/dev/null || echo "")

  if [[ "$host_hostname" == "$current_hostname" ]]; then
    local current_user
    current_user=$(resolve_current_hm_user "$repo_root" "$host")
    if [[ -n "$current_user" ]]; then
      printf '%s\n' "$current_user"
      return 0
    fi
  fi

  printf '%s\n' "$users"
}

find_cached_hm_activation_path() {
  local host="$1"
  local user="$2"
  local record
  for record in "${HM_ACTIVATION_RECORDS[@]}"; do
    IFS=$'\t' read -r record_host record_user record_path <<< "$record"
    if [[ "$record_host" == "$host" && "$record_user" == "$user" ]]; then
      printf '%s\n' "$record_path"
      return 0
    fi
  done

  return 1
}

# --- Build home-manager activation packages only (REQ-016.1-3) ---
# Builds home-manager activationPackage for each user on each host, returning
# cached "host:user:store-path" entries reused during deployment.
build_home_manager_only() {
  local repo_root="$1"
  shift
  local target_hosts=("$@")

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local build_targets=()
  local target_map=()   # host:user pairs
  HM_ACTIVATION_RECORDS=()

  for h in "${target_hosts[@]}"; do
    local users
    users=$(list_target_hm_users "$repo_root" "$h") || continue
    if [[ -z "$users" ]]; then
      echo "Warning: No home-manager users for host $h, skipping." >&2
      continue
    fi
    while IFS= read -r user; do
      build_targets+=("$repo_root#nixosConfigurations.$h.config.home-manager.users.\"$user\".home.activationPackage")
      target_map+=("$h:$user")
    done <<< "$users"
  done

  if [[ ${#build_targets[@]} -eq 0 ]]; then
    echo "Warning: No home-manager targets to build." >&2
    return 0
  fi

  echo "Building home-manager profiles: ${target_map[*]}..."
  local build_paths=()
  local build_output
  if ! build_output=$(nix build --no-link --print-out-paths "${build_targets[@]}" "${override_args[@]}"); then
    echo "Error: Home-manager build failed." >&2
    exit 1
  fi
  mapfile -t build_paths <<< "$build_output"

  local i
  for i in "${!target_map[@]}"; do
    IFS=':' read -r host user <<< "${target_map[$i]}"
    HM_ACTIVATION_RECORDS+=("$host"$'\t'"$user"$'\t'"${build_paths[$i]}")
  done

  echo "Home-manager build complete."
}

# --- Deploy home-manager profiles only (REQ-016.4-5) ---
# Activates home-manager profiles for each user on each target host.
# Does not require sudo — activation runs as the owning user.
deploy_home_manager_only() {
  local repo_root="$1"
  shift
  local target_hosts=("$@")

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local current_hostname
  current_hostname=$(hostname)
  local hosts_nix="$repo_root/hosts.nix"

  for host in "${target_hosts[@]}"; do
    local users
    users=$(list_target_hm_users "$repo_root" "$host") || continue
    [[ -z "$users" ]] && continue

    local host_json host_hostname ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    host_hostname=$(echo "$host_json" | jq -r '.hostname')
    ssh_target=$(resolve_ssh_target "$repo_root" "$host" "$host_json")
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')

    while IFS= read -r user; do
      # Resolve the activation package store path
      local activation_path
      activation_path=$(find_cached_hm_activation_path "$host" "$user") || activation_path=""
      if [[ -z "$activation_path" ]]; then
        activation_path=$(nix build --no-link --print-out-paths \
          "$repo_root#nixosConfigurations.$host.config.home-manager.users.\"$user\".home.activationPackage" \
          "${override_args[@]}" 2>/dev/null) || {
          echo "Error: Failed to resolve activation package for $user on $host" >&2
          continue
        }
      fi

      if [[ -z "$activation_path" ]]; then
        echo "Error: Failed to resolve activation package for $user on $host" >&2
        continue
      fi

      if [[ "$host_hostname" == "$current_hostname" ]]; then
        # LOCAL deploy — run activation as the user
        echo "Activating home-manager for $user on $host (local)..."
        sudo -u "$user" "$activation_path/activate" || {
          echo "Error: Activation failed for $user on $host" >&2
        }
      else
        # REMOTE deploy
        if [[ -z "$ssh_target" ]]; then
          echo "Error: $host has no sshTarget, cannot deploy remotely." >&2
          continue
        fi

        local resolved="$ssh_target"
        if [[ -n "$fallback_ip" ]]; then
          if ! ks_ssh_test "$ssh_target"; then
            resolved="$fallback_ip"
            echo "Tailscale unavailable for $host, using LAN: $fallback_ip"
          fi
        fi

        open_ssh_master "$resolved"

        echo "Activating home-manager for $user on $host (remote: $resolved)..."
        # Copy the closure to the remote host, then activate
        ks_nix_copy "$resolved" "$activation_path" "${override_args[@]}" 2>/dev/null || true
        # $user and $activation_path are intentionally expanded client-side
        # shellcheck disable=SC2029
        ks_ssh "$resolved" "sudo -u '$user' '$activation_path/activate'" || {
          echo "Error: Remote activation failed for $user on $host" >&2
        }
      fi
    done <<< "$users"
  done
}

# --- Find local repo path ---
# Returns the local path for a given repo registry key (owner/repo).
find_local_repo() {
  local repo_root="$1" key="$2"
  local name="${key##*/}"

  if [[ -d "$HOME/.keystone/repos/$key" ]]; then
    echo "$HOME/.keystone/repos/$key"
  elif [[ -d "$repo_root/.repos/$name" ]]; then
    echo "$repo_root/.repos/$name"
  elif [[ -d "$repo_root/.submodules/$name" ]]; then
    echo "$repo_root/.submodules/$name"
  elif [[ -d "$repo_root/$name" ]]; then
    echo "$repo_root/$name"
  fi
}

# --- Pull (clone or update) a repo ---
pull_repo() {
  local repo_root="$1" key="$2" url="$3"
  local target="$HOME/.keystone/repos/$key"

  # Check for existing checkout in legacy locations
  local existing
  existing=$(find_local_repo "$repo_root" "$key")
  if [[ -n "$existing" ]]; then
    target="$existing"
  fi

  if [[ -e "$target/.git" ]]; then
    # Detect detached HEAD and recover by switching to the default branch before pulling
    if ! git -C "$target" symbolic-ref HEAD >/dev/null 2>&1; then
      local default_branch
      default_branch=$(git -C "$target" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
      default_branch="${default_branch:-main}"
      echo "Warning: $key is in detached HEAD state, switching to $default_branch..." >&2
      git -C "$target" checkout "$default_branch" || {
        echo "Error: failed to checkout $default_branch in $key" >&2
        return 1
      }
    fi
    echo "Pulling $key..."
    run_with_warning_filter git -C "$target" pull --ff-only
  else
    echo "Cloning $key..."
    mkdir -p "$(dirname "$target")"
    git clone "$url" "$target"
  fi
}

bootstrap_managed_repos() {
  local repo_root="$1"
  local registry="$2"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key url
    key=$(echo "$line" | cut -d'|' -f1)
    url=$(echo "$line" | cut -d'|' -f2)
    pull_repo "$repo_root" "$key" "$url"
  done <<< "$(echo "$registry" | jq -r 'to_entries[] | "\(.key)|\(.value.url)"')"
}

# --- Verify repo is lock-ready for automated sync ---
verify_repo_lock_ready() {
  local path="$1" name="$2"
  if [[ ! -d "$path" ]]; then
    return 0
  fi
  if ! git -C "$path" diff --quiet || ! git -C "$path" diff --cached --quiet; then
    echo "Error: $name has uncommitted changes at $path" >&2
    exit 1
  fi
  if [[ -n "$(git -C "$path" ls-files --others --exclude-standard)" ]]; then
    echo "Error: $name has untracked files at $path" >&2
    exit 1
  fi
  local branch
  branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
  if [[ -z "$branch" ]]; then
    echo "Error: $name is in detached HEAD state at $path" >&2
    exit 1
  fi
}

push_repo_for_lock() {
  local path="$1" name="$2"
  [[ ! -d "$path" ]] && return 0

  local branch upstream counts behind ahead
  branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
  if [[ -z "$branch" ]]; then
    echo "Error: $name is in detached HEAD state at $path" >&2
    exit 1
  fi

  upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null || echo "")
  if [[ -n "$upstream" ]]; then
    counts=$(git -C "$path" rev-list --left-right --count "${upstream}...HEAD")
    read -r behind ahead <<<"$counts"

    if (( behind > 0 )); then
      echo "Rebasing $name onto $upstream..."
      if ! run_with_warning_filter git -C "$path" pull --rebase; then
        echo "" >&2
        echo "ERROR: Failed to rebase $name onto $upstream." >&2
        echo "Resolve conflicts in $path, then rerun the command." >&2
        exit 1
      fi

      counts=$(git -C "$path" rev-list --left-right --count "${upstream}...HEAD")
      read -r behind ahead <<<"$counts"
      if (( behind > 0 )); then
        echo "Error: $name is still behind $upstream at $path after rebase" >&2
        exit 1
      fi
    fi

    if (( ahead == 0 )); then
      return 0
    fi
  fi

  if [[ "$name" == "ncrmro/keystone" ]]; then
    push_keystone_with_fork_fallback "$path"
    return 0
  fi

  if [[ -n "$upstream" ]]; then
    echo "Pushing $name..."
    run_with_warning_filter git -C "$path" push
  else
    echo "Pushing $name (setting upstream)..."
    run_with_warning_filter git -C "$path" push -u origin "$branch"
  fi
}

record_local_system_flake() {
  local repo_root="$1"
  [[ -z "$repo_root" ]] && return 0

  if is_root_user; then
    install -d -m 0755 /etc/keystone
    printf '%s\n' "$repo_root" > /etc/keystone/system-flake
  else
    sudo install -d -m 0755 /etc/keystone
    printf '%s\n' "$repo_root" | sudo tee /etc/keystone/system-flake >/dev/null
  fi
}

# --- Build and deploy current unlocked state ---
deploy_unlocked_current_state() {
  local repo_root="$1"
  local mode="$2"
  shift 2
  local target_hosts=("$@")
  local hosts_nix="$repo_root/hosts.nix"

  local needs_sudo=false current_hostname
  current_hostname=$(hostname)
  for h in "${target_hosts[@]}"; do
    local h_hostname
    h_hostname=$(nix eval -f "$hosts_nix" "$h.hostname" --raw)
    if [[ "$h_hostname" == "$current_hostname" ]]; then
      needs_sudo=true
      break
    fi
  done

  if [[ "$needs_sudo" == true ]]; then
    if is_root_user; then
      echo "Running unlocked deployment as root..."
    else
      echo "Caching sudo credentials..."
      sudo -v
    fi
  fi

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local build_targets=()
  for h in "${target_hosts[@]}"; do
    build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
  done

  echo "Building current unlocked state: ${target_hosts[*]}..."
  local build_paths=()
  if ! mapfile -t build_paths < <(nix build --no-link --print-out-paths "${build_targets[@]}" "${override_args[@]}"); then
    echo "Error: build failed for current unlocked state." >&2
    return 1
  fi

  if [[ ${#build_paths[@]} -ne ${#target_hosts[@]} ]]; then
    echo "Error: nix build returned ${#build_paths[@]} path(s) for ${#target_hosts[@]} target host(s)." >&2
    return 1
  fi

  for i in "${!target_hosts[@]}"; do
    local host="${target_hosts[$i]}"
    local path="${build_paths[$i]}"
    local host_json ssh_target fallback_ip host_hostname
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(resolve_ssh_target "$repo_root" "$host" "$host_json")
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')
    host_hostname=$(echo "$host_json" | jq -r '.hostname')

    if [[ "$host_hostname" == "$current_hostname" ]]; then
      local current_system
      current_system=$(readlink -f /run/current-system 2>/dev/null || echo "none")

      if [[ "$current_system" == "$(readlink -f "$path")" ]]; then
        echo "System closure unchanged. Activating fast home-manager switch locally..."
        deploy_home_manager_only "$repo_root" "$host"
        run_root_command nix-env -p /nix/var/nix/profiles/system --set "$path"
        echo "Skipped switch-to-configuration for $host because the system closure is unchanged."
      else
        echo "Deploying $host locally ($mode)..."
        run_root_command nix-env -p /nix/var/nix/profiles/system --set "$path"
        run_root_command touch /var/run/nixos-rebuild-safe-to-update-bootloader
        run_root_command "$path/bin/switch-to-configuration" "$mode"
      fi
      record_local_system_flake "$repo_root"
    else
      if [[ -z "$ssh_target" ]]; then
        echo "Error: $host has no sshTarget (local-only host). Cannot deploy remotely." >&2
        exit 1
      fi
      local resolved="$ssh_target"
      if [[ -n "$fallback_ip" ]]; then
        if ! ks_ssh_test "$ssh_target"; then
          resolved="$fallback_ip"
        fi
      fi

      open_ssh_master "$resolved"

      echo "Deploying $host to root@$resolved ($mode)..."
      ks_nix_copy "$resolved" "$path"

      local check_cmd remote_status
      check_cmd="
        current_system=\$(readlink -f /run/current-system 2>/dev/null || echo 'none')
        if [[ \"\$current_system\" != \"$(readlink -f "$path")\" ]]; then
          echo 'OS'
        else
          echo 'HM'
        fi
      "
      # shellcheck disable=SC2029  # $path intentionally expanded client-side before the string is sent to the remote shell
      remote_status=$(ks_ssh "$resolved" "$check_cmd")

      if [[ "$remote_status" == "HM" ]]; then
        echo "OS core unchanged. Activating fast home-manager switch remotely..."
        deploy_home_manager_only "$repo_root" "$host"
        # shellcheck disable=SC2029  # $path intentionally expanded client-side; remote only receives the resolved store path string
        ks_ssh "$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path"
        echo "Skipped switch-to-configuration for $host because the system closure is unchanged."
      else
        # shellcheck disable=SC2029  # $path and $mode intentionally expanded client-side; remote receives the resolved store path and mode strings
        ks_ssh "$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path && touch /var/run/nixos-rebuild-safe-to-update-bootloader && $path/bin/switch-to-configuration $mode"
      fi
      close_ssh_master "$resolved"
    fi

    [[ "$mode" == "boot" ]] && echo "Reboot required to apply changes for $host."
    echo "Update complete for $host"
  done
  close_all_ssh_masters
  maybe_sync_grafana_dashboards "$repo_root"
}

# --- Commands ---

cmd_sync_host_keys() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help)
        print_sync_host_keys_help
        return 0
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  fi

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"

  # Get all host keys
  local all_hosts
  all_hosts=$(nix eval -f "$hosts_nix" --json --apply 'builtins.attrNames')
  local host_list
  host_list=$(echo "$all_hosts" | jq -r '.[]')

  local changed=0 skipped=0 failed=0

  for host in $host_list; do
    local host_json ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(resolve_ssh_target "$repo_root" "$host" "$host_json")

    if [[ -z "$ssh_target" ]]; then
      echo "SKIP $host (no sshTarget)"
      ((skipped++)) || true
      continue
    fi

    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')

    # Resolve SSH target with Tailscale → LAN fallback
    local resolved="$ssh_target"
    if ! ks_ssh_test "$ssh_target"; then
      if [[ -n "$fallback_ip" ]]; then
        resolved="$fallback_ip"
        echo "  Tailscale unavailable for $host, using LAN: $fallback_ip"
      else
        echo "FAIL $host (unreachable via $ssh_target)"
        ((failed++)) || true
        continue
      fi
    fi

    open_ssh_master "$resolved"

    # Fetch host public key
    local pubkey
    pubkey=$(ks_ssh "$resolved" \
      'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>/dev/null | awk '{print $1" "$2}') || true

    if [[ -z "$pubkey" ]]; then
      echo "FAIL $host (could not read host key from $resolved)"
      ((failed++)) || true
      continue
    fi

    # Check current value
    local current
    current=$(echo "$host_json" | jq -r '.hostPublicKey // empty')

    if [[ "$pubkey" == "$current" ]]; then
      echo "  OK $host (unchanged)"
      continue
    fi

    # Update hosts.nix — insert or replace hostPublicKey
    if [[ -n "$current" ]]; then
      # Replace existing hostPublicKey line
      sed -i "s|hostPublicKey = \"${current}\";|hostPublicKey = \"${pubkey}\";|" "$hosts_nix"
    else
      # Insert hostPublicKey after the role line for this host
      sed -i "/^  ${host} = {/,/^  };/ s|role = \"[^\"]*\";|&\n    hostPublicKey = \"${pubkey}\";|" "$hosts_nix"
    fi

    echo "  SET $host → ${pubkey:0:40}..."
    ((changed++)) || true
  done

  echo ""
  echo "Summary: $changed updated, $skipped skipped, $failed failed"
  if [[ $changed -gt 0 ]]; then
    echo "Review changes with: git diff hosts.nix"
  fi
}

cmd_build() {
  local hosts_arg="" lock=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_build_help
        return 0
        ;;
      --dev) shift ;;  # kept for backwards compat, no-op
      --lock) lock=true; shift ;;
      --user)
        [[ $# -lt 2 ]] && { echo "Error: --user requires a value" >&2; exit 1; }
        KS_HM_USERS_FILTER="$2"
        shift 2
        ;;
      --all-users)
        KS_HM_ALL_USERS=true
        shift
        ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) hosts_arg="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"

  local target_hosts=()
  if [[ -z "$hosts_arg" ]]; then
    target_hosts+=("$(resolve_host "$hosts_nix" "")")
  else
    # Split by comma
    IFS=',' read -ra ADDR <<< "$hosts_arg"
    for h in "${ADDR[@]}"; do
      target_hosts+=("$(resolve_host "$hosts_nix" "$h")")
    done
  fi

  if [[ "$lock" == true ]]; then
    # ── LOCK MODE (REQ-016.7): full system build with lock workflow ──
    # Step 1: Verify repos are lock-ready
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local path
      path=$(find_local_repo "$repo_root" "$key")
      [[ -n "$path" ]] && verify_repo_lock_ready "$path" "$key"
    done <<< "$(get_repos_registry "$repo_root" | jq -r 'to_entries[].key')"

    # Step 2: Push managed flake repos that are ahead of their upstream.
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local path
      path=$(find_local_repo "$repo_root" "$key")
      [[ -n "$path" ]] && push_repo_for_lock "$path" "$key"
    done <<< "$(get_repos_registry "$repo_root" | jq -r 'to_entries[] | select(.value.flakeInput != null) | .key')"

    # Step 3: Lock flake inputs
    echo "Locking flake inputs..."
    local inputs
    inputs=$(get_repos_registry "$repo_root" | jq -r 'to_entries[].value.flakeInput | select(. != null)')
    # shellcheck disable=SC2086  # $inputs is a space-separated list; word-splitting is intentional to pass each input as a separate argument
    nix flake update $inputs --flake "$repo_root"

    # Step 4: Full system build with local overrides (REQ-019.5)
    local override_args=()
    read -ra override_args <<< "$(local_override_args "$repo_root")"
    local build_targets=()
    for h in "${target_hosts[@]}"; do
      build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
    done
    echo "Building (full system): ${target_hosts[*]}..."
    nix build --no-link "${build_targets[@]}" "${override_args[@]}"

    # Step 5: Commit flake.lock only after successful build (REQ-019.8)
    if ! git -C "$repo_root" diff --quiet flake.lock; then
      echo "Committing flake.lock..."
      git -C "$repo_root" add flake.lock
      git -C "$repo_root" commit -m "chore: relock keystone + agenix-secrets"
    fi

    # Step 6: Push nixos-config
    echo "Pushing nixos-config..."
    push_repo_for_lock "$repo_root" "nixos-config"
    echo "Lock + build complete for: ${target_hosts[*]}"
  else
    # ── DEFAULT MODE (REQ-016.1): home-manager only build ──
    build_home_manager_only "$repo_root" "${target_hosts[@]}"
  fi
}

# --- Switch command (fast deploy) ---
cmd_switch() {
  local mode="switch" hosts_arg=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_switch_help
        return 0
        ;;
      --boot) mode="boot"; shift ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) hosts_arg="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"
  KS_HM_USERS_FILTER=""
  KS_HM_ALL_USERS=false
  HM_ACTIVATION_RECORDS=()

  local target_hosts=()
  if [[ -z "$hosts_arg" ]]; then
    target_hosts+=("$(resolve_host "$hosts_nix" "")")
  else
    # Split by comma
    IFS=',' read -ra ADDR <<< "$hosts_arg"
    for h in "${ADDR[@]}"; do
      target_hosts+=("$(resolve_host "$hosts_nix" "$h")")
    done
  fi

  deploy_unlocked_current_state "$repo_root" "$mode" "${target_hosts[@]}"
}

# --- Install command (interactive ISO installer flow) ---
cmd_install() {
  local force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_install_help
        return 0
        ;;
      --force)
        force=true
        shift
        ;;
      -*)
        echo "Error: Unknown option '$1'" >&2
        print_install_help >&2
        return 1
        ;;
      *)
        echo "Error: Unexpected argument '$1'" >&2
        print_install_help >&2
        return 1
        ;;
    esac
  done

  if ! command -v keystone-tui >/dev/null 2>&1; then
    echo "Error: keystone-tui is not available in PATH." >&2
    echo "Enable the installer TUI package in the ISO environment first." >&2
    return 1
  fi

  if [[ ! -f /etc/NIXOS && "$force" != true ]]; then
    echo "Error: ks install is intended for a booted NixOS installer environment." >&2
    echo "Use --force to bypass this check." >&2
    return 1
  fi

  if [[ ! -d /etc/keystone/install-repo && ! -d /etc/keystone/install-config ]]; then
    echo "Error: installer data is missing." >&2
    echo "Boot an installer image with an embedded install repo or legacy install-config bundle, then retry." >&2
    return 1
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    exec keystone-tui --install
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: ks install needs sudo to launch the installer as root." >&2
    echo "The live Keystone installer ISO should provide non-interactive sudo for the admin user." >&2
    return 1
  fi

  if ! sudo -n true >/dev/null 2>&1; then
    echo "Error: ks install needs non-interactive sudo in the live installer environment." >&2
    echo "Rebuild or boot a Keystone installer ISO that grants passwordless sudo to the admin user." >&2
    return 1
  fi

  exec sudo -n -- keystone-tui --install
}

# --- Update command ---
cmd_update() {
  local mode="switch" hosts_arg="" pull=false lock=true
  KS_HM_USERS_FILTER=""
  KS_HM_ALL_USERS=false
  HM_ACTIVATION_RECORDS=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_update_help
        return 0
        ;;
      --debug) KS_DEBUG=true; shift ;;
      --dev) lock=false; shift ;;
      --boot) mode="boot"; shift ;;
      --pull) pull=true; shift ;;
      --lock) lock=true; shift ;;
      --user)
        [[ $# -lt 2 ]] && { echo "Error: --user requires a value" >&2; exit 1; }
        KS_HM_USERS_FILTER="$2"
        shift 2
        ;;
      --all-users)
        KS_HM_ALL_USERS=true
        shift
        ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) hosts_arg="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"

  local target_hosts=()
  if [[ -z "$hosts_arg" ]]; then
    target_hosts+=("$(resolve_host "$hosts_nix" "")")
  else
    # Split by comma
    IFS=',' read -ra ADDR <<< "$hosts_arg"
    for h in "${ADDR[@]}"; do
      target_hosts+=("$(resolve_host "$hosts_nix" "$h")")
    done
  fi

  local registry
  registry=$(get_repos_registry "$repo_root")

  # --- Handle --pull (standalone, no lock) ---
  if [[ "$pull" == true && "$lock" != true ]]; then
    bootstrap_managed_repos "$repo_root" "$registry"
    echo "Pull complete."
    return
  fi

  # ── DEV MODE: deploy current unlocked checkout without lock/push ─────────────
  if [[ "$lock" != true ]]; then
    deploy_unlocked_current_state "$repo_root" "$mode" "${target_hosts[@]}"
    echo "Dev mode update complete (current unlocked checkout) for: ${target_hosts[*]}"
    return
  fi

  # ── LOCK MODE: full system rebuild ──────────────────────────────────────────

  # Step 1: Cache sudo credentials immediately — before any pull, lock, or build.
  # Any update that reaches this point may deploy locally; prompt upfront so the
  # user is not interrupted later.
  local needs_sudo=false
  local current_hostname
  current_hostname=$(hostname)
  for h in "${target_hosts[@]}"; do
    local h_hostname
    h_hostname=$(nix eval -f "$hosts_nix" "$h.hostname" --raw)
    if [[ "$h_hostname" == "$current_hostname" ]]; then
      needs_sudo=true
      break
    fi
  done

  SUDO_KEEPALIVE_PID=""
  if [[ "$needs_sudo" == true ]]; then
    if is_root_user; then
      echo "Running update as root..."
    else
      echo "Caching sudo credentials (needed for local deploy)..."
      sudo -v
      # Keepalive: refresh every 60 s so a long pull/lock/build doesn't expire the ticket.
      ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 60; done ) &
      SUDO_KEEPALIVE_PID=$!
      trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; trap - EXIT' EXIT
    fi
  fi

  # ── UPFRONT PHASE ───────────────────────────────────────────────────────────
  # Step 1: Pull nixos-config so we operate on latest
  echo "Pulling nixos-config..."
  run_with_warning_filter git -C "$repo_root" pull --ff-only

  # Step 2: Pull all repos in registry
  bootstrap_managed_repos "$repo_root" "$registry"

  # Step 3: Verify repos are lock-ready before locking
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    local path
    path=$(find_local_repo "$repo_root" "$key")
    [[ -n "$path" ]] && verify_repo_lock_ready "$path" "$key"
  done <<< "$(echo "$registry" | jq -r 'to_entries[].key')"

  # Step 3.5: Push managed flake repos that are ahead of their upstream.
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    local path
    path=$(find_local_repo "$repo_root" "$key")
    [[ -n "$path" ]] && push_repo_for_lock "$path" "$key"
  done <<< "$(echo "$registry" | jq -r 'to_entries[] | select(.value.flakeInput != null) | .key')"

  # Step 4: Update flake.lock BEFORE building so the build validates what will be committed
  echo "Locking flake inputs..."
  local inputs
  inputs=$(echo "$registry" | jq -r 'to_entries[].value.flakeInput | select(. != null)')
  # shellcheck disable=SC2086  # $inputs is a space-separated list; word-splitting is intentional to pass each input as a separate argument
  run_with_warning_filter nix flake update $inputs --flake "$repo_root"

  # Step 5: Commit flake.lock (if changed)
  if ! git -C "$repo_root" diff --quiet flake.lock; then
    echo "Committing flake.lock..."
    git -C "$repo_root" add flake.lock
    git -C "$repo_root" commit -m "chore: relock keystone + agenix-secrets"
  fi

  # Always use local overrides when repos are present
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  # ── BUILD PHASE ─────────────────────────────────────────────────────────────
  # Step 7: Build all targets in a single invocation (nix parallelises internally)
  local build_targets=()
  for h in "${target_hosts[@]}"; do
    build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
  done

  echo "Building: ${target_hosts[*]}..."
  local build_paths=()
  if ! mapfile -t build_paths < <(run_with_warning_filter nix build --no-link --print-out-paths "${build_targets[@]}" "${override_args[@]}"); then
    local rerun_cmd="ks update"
    if [[ "${KS_DEBUG}" == true ]]; then
      rerun_cmd+=" --debug"
    fi
    if [[ "$mode" == "boot" ]]; then
      rerun_cmd+=" --boot"
    fi
    rerun_cmd+=" --lock"
    if [[ -n "$hosts_arg" ]]; then
      rerun_cmd+=" $hosts_arg"
    fi
    echo ""
    echo "ERROR: Build failed."
    echo "Fix the build errors above, then rerun: $rerun_cmd"
    exit 1
  fi

  # ── POST-BUILD PHASE ────────────────────────────────────────────────────────
  # Step 8: Push flake.lock only after a successful build
  echo "Pushing nixos-config..."
  if ! run_with_warning_filter git -C "$repo_root" pull --rebase origin "$(git -C "$repo_root" branch --show-current)"; then
    echo ""
    echo "ERROR: Failed to rebase nixos-config against origin."
    echo "Resolve conflicts manually, then run: git push"
    exit 1
  fi
  if ! run_with_warning_filter git -C "$repo_root" push; then
    echo ""
    echo "ERROR: Failed to push nixos-config."
    echo "Run 'git pull --rebase && git push' to retry."
    exit 1
  fi

  # Step 7: Deploy sequentially using the built store paths
  for i in "${!target_hosts[@]}"; do
    local host="${target_hosts[$i]}"
    local path="${build_paths[$i]}"
    local host_json ssh_target fallback_ip host_hostname
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(resolve_ssh_target "$repo_root" "$host" "$host_json")
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')
    host_hostname=$(echo "$host_json" | jq -r '.hostname')

    if [[ "$host_hostname" == "$current_hostname" ]]; then
      local old_sw new_sw old_kernel new_kernel old_initrd new_initrd etc_changed=false
      old_sw=$(readlink -f /run/current-system/sw 2>/dev/null || echo "old")
      new_sw=$(readlink -f "$path/sw" 2>/dev/null || echo "new")
      old_kernel=$(readlink -f /run/current-system/kernel 2>/dev/null || echo "old")
      new_kernel=$(readlink -f "$path/kernel" 2>/dev/null || echo "new")
      old_initrd=$(readlink -f /run/current-system/initrd 2>/dev/null || echo "old")
      new_initrd=$(readlink -f "$path/initrd" 2>/dev/null || echo "new")

      if ! diff -r -q --exclude="per-user" "$(readlink -f /run/current-system/etc)" "$(readlink -f "$path/etc")" >/dev/null 2>&1; then
        etc_changed=true
      fi

      if [[ "$old_sw" == "$new_sw" && "$old_kernel" == "$new_kernel" && "$old_initrd" == "$new_initrd" && "$etc_changed" == false ]]; then
        echo "OS core unchanged. Activating fast home-manager switch locally..."
        deploy_home_manager_only "$repo_root" "$host"
        run_root_command nix-env -p /nix/var/nix/profiles/system --set "$path"
        run_root_command touch /var/run/nixos-rebuild-safe-to-update-bootloader
        run_root_command "$path/bin/switch-to-configuration" boot
      else
        echo "Deploying $host locally ($mode)..."
        run_root_command nix-env -p /nix/var/nix/profiles/system --set "$path"
        run_root_command touch /var/run/nixos-rebuild-safe-to-update-bootloader
        run_root_command "$path/bin/switch-to-configuration" "$mode"
      fi
      record_local_system_flake "$repo_root"
    else
      if [[ -z "$ssh_target" ]]; then
        echo "Error: $host has no sshTarget (local-only host). Cannot deploy remotely." >&2; exit 1
      fi
      local resolved="$ssh_target"
      if [[ -n "$fallback_ip" ]]; then
        if ! ks_ssh_test "$ssh_target"; then
          resolved="$fallback_ip"
        fi
      fi

      open_ssh_master "$resolved"

      echo "Deploying $host to root@$resolved ($mode)..."
      ks_nix_copy "$resolved" "$path"

      # Check remote OS state
      local new_sw new_kernel new_initrd check_cmd remote_status
      new_sw=$(readlink -f "$path/sw" 2>/dev/null || echo "new")
      new_kernel=$(readlink -f "$path/kernel" 2>/dev/null || echo "new")
      new_initrd=$(readlink -f "$path/initrd" 2>/dev/null || echo "new")

      check_cmd="
        old_sw=\$(readlink -f /run/current-system/sw 2>/dev/null || echo 'old')
        old_kernel=\$(readlink -f /run/current-system/kernel 2>/dev/null || echo 'old')
        old_initrd=\$(readlink -f /run/current-system/initrd 2>/dev/null || echo 'old')
        if [[ \"\$old_sw\" == \"$new_sw\" && \"\$old_kernel\" == \"$new_kernel\" && \"\$old_initrd\" == \"$new_initrd\" ]]; then
          if ! diff -r -q --exclude='per-user' \"\$(readlink -f /run/current-system/etc)\" \"\$(readlink -f $path/etc)\" >/dev/null 2>&1; then
            echo 'OS'
          else
            echo 'HM'
          fi
        else
          echo 'OS'
        fi
      "
      # shellcheck disable=SC2029  # $new_sw, $new_kernel, $new_initrd, $path intentionally expanded client-side before the string is sent to the remote shell
      remote_status=$(ks_ssh "$resolved" "$check_cmd")

      if [[ "$remote_status" == "HM" ]]; then
        echo "OS core unchanged. Activating fast home-manager switch remotely..."
        deploy_home_manager_only "$repo_root" "$host"
        # shellcheck disable=SC2029  # $path intentionally expanded client-side; remote only receives the resolved store path string
        ks_ssh "$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path && touch /var/run/nixos-rebuild-safe-to-update-bootloader && $path/bin/switch-to-configuration boot"
      else
        # shellcheck disable=SC2029  # $path and $mode intentionally expanded client-side; remote receives the resolved store path and mode strings
        ks_ssh "$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path && touch /var/run/nixos-rebuild-safe-to-update-bootloader && $path/bin/switch-to-configuration $mode"
      fi
      close_ssh_master "$resolved"
    fi

    [[ "$mode" == "boot" ]] && echo "Reboot required to apply changes for $host."
    echo "Update complete for $host"
  done
  close_all_ssh_masters
  maybe_sync_grafana_dashboards "$repo_root"
}

# --- Find keystone repo (where conventions/ lives) ---
# Returns the path to the local keystone repo clone, or empty string if not found.
find_keystone_repo() {
  local repo_root="$1"
  local ks_path
  ks_path=$(find_local_repo "$repo_root" "ncrmro/keystone")
  echo "${ks_path:-}"
}

# --- Load conventions from keystone repo ---
# Concatenates all *.md files from conventions/ in the keystone repo.
# Prints nothing (no error) if the directory is not found.
load_conventions() {
  local ks_repo="$1"
  if [[ -z "$ks_repo" || ! -d "$ks_repo/conventions" ]]; then
    return 0
  fi
  local first=true
  for f in "$ks_repo/conventions"/*.md; do
    [[ -f "$f" ]] || continue
    if [[ "$first" == true ]]; then
      first=false
    else
      echo ""
      echo "---"
      echo ""
    fi
    cat "$f"
  done
}

grafana_dashboards_dir() {
  local repo_root="$1"
  local ks_repo
  ks_repo=$(find_keystone_repo "$repo_root")

  if [[ -n "$ks_repo" && -d "$ks_repo/modules/server/services/grafana/dashboards" ]]; then
    printf '%s\n' "$ks_repo/modules/server/services/grafana/dashboards"
    return
  fi

  if [[ -d "$repo_root/modules/server/services/grafana/dashboards" ]]; then
    printf '%s\n' "$repo_root/modules/server/services/grafana/dashboards"
    return
  fi

  echo "Error: could not locate keystone Grafana dashboards directory." >&2
  exit 1
}

grafana_managed_tag() {
  printf '%s\n' "keystone-managed"
}

grafana_api_request() {
  local method="$1"
  local url="$2"
  local api_key="$3"
  local data="${4:-}"
  local body_file
  local http_code

  body_file=$(mktemp)
  if [[ -n "$data" ]]; then
    http_code=$(curl -sS -o "$body_file" -w '%{http_code}' \
      -H "Authorization: Bearer ${api_key}" \
      -H 'Content-Type: application/json' \
      -X "$method" \
      --data "$data" \
      "$url")
  else
    http_code=$(curl -sS -o "$body_file" -w '%{http_code}' \
      -H "Authorization: Bearer ${api_key}" \
      -X "$method" \
      "$url")
  fi

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "Grafana API request failed: ${method} ${url} (HTTP ${http_code})" >&2
    if [[ -s "$body_file" ]]; then
      cat "$body_file" >&2
      echo >&2
    fi
    rm -f "$body_file"
    return 1
  fi

  cat "$body_file"
  rm -f "$body_file"
}

keystone_development_enabled() {
  local repo_root="$1"
  local current_host
  current_host=$(resolve_host "$repo_root/hosts.nix" "")

  local value
  value=$(nix eval "$repo_root#nixosConfigurations.${current_host}.config.keystone.development" --json 2>/dev/null || echo "false")
  ks_bool_true "$(echo "$value" | jq -r '.')"
}

maybe_sync_grafana_dashboards() {
  local repo_root="$1"

  if ! keystone_development_enabled "$repo_root"; then
    return 0
  fi

  echo "Syncing keystone Grafana dashboards via API..."
  cmd_grafana "dashboards" "apply"
}

resolve_grafana_url() {
  local repo_root="$1"
  if [[ -n "${GRAFANA_URL:-}" ]]; then
    printf '%s\n' "$GRAFANA_URL"
    return
  fi

  local hosts_nix="$repo_root/hosts.nix"
  if [[ ! -f "$hosts_nix" ]]; then
    echo "Error: hosts.nix not found while resolving Grafana URL." >&2
    exit 1
  fi

  local current_hostname current_host domain subdomain grafana_host=""
  current_hostname=$(hostname)
  current_host=$(nix eval -f "$hosts_nix" --raw \
    --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current_hostname\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m" \
    2>/dev/null || true)

  # Try to find a host with grafana enabled
  if [[ -n "$current_host" ]]; then
    if [[ "$(nix eval "$repo_root#nixosConfigurations.${current_host}.config.keystone.server.services.grafana.enable" --json 2>/dev/null)" == "true" ]]; then
      grafana_host="$current_host"
    fi
  fi

  if [[ -z "$grafana_host" ]]; then
    # Scan all server hosts for grafana.enable
    local server_hosts
    server_hosts=$(nix eval -f "$hosts_nix" --json --apply "hosts: builtins.filter (k: (builtins.getAttr k hosts).role == \"server\") (builtins.attrNames hosts)" 2>/dev/null || echo "[]")
    for host in $(echo "$server_hosts" | jq -r '.[]'); do
      if [[ "$(nix eval "$repo_root#nixosConfigurations.${host}.config.keystone.server.services.grafana.enable" --json 2>/dev/null)" == "true" ]]; then
        grafana_host="$host"
        break
      fi
    done
  fi

  if [[ -z "$grafana_host" ]]; then
    echo "Error: could not find any host with keystone.server.services.grafana.enable = true. Set GRAFANA_URL." >&2
    exit 1
  fi

  subdomain=$(nix eval "$repo_root#nixosConfigurations.${grafana_host}.config.keystone.server.services.grafana.subdomain" --raw 2>/dev/null || printf 'grafana')
  domain=$(nix eval "$repo_root#nixosConfigurations.${grafana_host}.config.keystone.domain" --raw 2>/dev/null || true)

  if [[ -z "$domain" ]]; then
    echo "Error: could not resolve Grafana URL from config for host '$grafana_host'. Set GRAFANA_URL." >&2
    exit 1
  fi

  printf 'https://%s.%s\n' "$subdomain" "$domain"
}

resolve_grafana_api_key() {
  local repo_root="${1:-}"

  # 1. Runtime agenix secret (fastest, no decryption overhead)
  if [[ -f /run/agenix/grafana-api-token ]]; then
    tr -d '\n' < /run/agenix/grafana-api-token
    return
  fi

  # 2. Decrypt from agenix-secrets repo using age directly
  if [[ -n "$repo_root" ]]; then
    local secrets_repo
    secrets_repo=$(find_local_repo "$repo_root" "ncrmro/agenix-secrets")
    local age_file="${secrets_repo}/secrets/grafana-api-token.age"
    if [[ -n "$secrets_repo" && -f "$age_file" ]]; then
      # Resolve the age binary from the agenix wrapper (avoids hardcoding nix store paths)
      local age_bin
      age_bin=$(grep -o '/nix/store/[^"]*bin/age' "$(command -v agenix)" 2>/dev/null | head -1)
      [[ -z "$age_bin" || ! -x "$age_bin" ]] && return 1
      local decrypted
      # Try host key via sudo (works when sudo credentials are cached)
      local host_key="/etc/ssh/ssh_host_ed25519_key"
      if [[ -f "$host_key" ]]; then
        decrypted=$(sudo -n "$age_bin" -d -i "$host_key" "$age_file" 2>/dev/null | tr -d '\n')
        if [[ -n "$decrypted" ]]; then
          printf '%s' "$decrypted"
          return
        fi
      fi
      # Try user SSH key (works when terminal is available for passphrase prompt)
      local user_key="$HOME/.ssh/id_ed25519"
      if [[ -f "$user_key" ]]; then
        decrypted=$("$age_bin" -d -i "$user_key" "$age_file" 2>/dev/null | tr -d '\n')
        if [[ -n "$decrypted" ]]; then
          printf '%s' "$decrypted"
          return
        fi
      fi
    fi
  fi

  return 1
}

cmd_grafana_dashboards() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help)
      print_grafana_dashboards_help
      return 0
      ;;
    "")
      echo "Error: Missing grafana dashboards action" >&2
      print_grafana_dashboards_help >&2
      exit 1
      ;;
  esac

  local repo_root dashboards_dir grafana_url grafana_api_key
  repo_root=$(find_repo)
  dashboards_dir=$(grafana_dashboards_dir "$repo_root")
  
  grafana_url=$(resolve_grafana_url "$repo_root" 2>/dev/null || true)
  if [[ -z "$grafana_url" ]]; then
    if keystone_development_enabled "$repo_root"; then
      echo "Error: could not resolve Grafana URL for dashboard sync in development mode. Set GRAFANA_URL." >&2
      return 1
    fi
    echo "Warning: skipping dashboard sync (could not resolve Grafana URL). Set GRAFANA_URL." >&2
    return 0
  fi

  grafana_api_key=$(resolve_grafana_api_key "$repo_root" 2>/dev/null || true)
  if [[ -z "$grafana_api_key" ]]; then
    if keystone_development_enabled "$repo_root"; then
      echo "Error: Keystone Grafana API token is required for dashboard sync in development mode." >&2
      echo "Define 'secrets/grafana-api-token.age' for this host and rebuild." >&2
      return 1
    fi
    echo "Warning: Keystone Grafana API token is not configured on this host." >&2
    echo "To enable dashboard synchronization and Grafana MCP, you must:" >&2
    echo "  1. Define 'secrets/grafana-api-token.age' in your nixos-config/secrets.nix" >&2
    echo "  2. Assign it to this host's public key" >&2
    echo "  3. Rebuild and switch this host: ks switch" >&2
    echo "" >&2
    # TODO: In the future, keystone can automate this by submitting a PR to your nixos-config.
    return 0
  fi

  case "$action" in
    apply)
      local file uid payload managed_tag
      local -a desired_uids remote_managed_uids
      managed_tag=$(grafana_managed_tag)
      shopt -s nullglob
      for file in "$dashboards_dir"/*.json; do
        uid=$(jq -r '.uid // empty' "$file")
        if [[ -z "$uid" ]]; then
          echo "Skipping $file (missing uid)" >&2
          continue
        fi
        desired_uids+=("$uid")
        payload=$(jq -cn --slurpfile dashboard "$file" --arg managed_tag "$managed_tag" '
          {
            dashboard: (
              $dashboard[0]
              | .tags = (((.tags // []) + [$managed_tag]) | unique)
            ),
            overwrite: true
          }
        ')
        grafana_api_request POST \
          "${grafana_url}/api/dashboards/db" \
          "${grafana_api_key}" \
          "$payload" >/dev/null
        echo "Applied ${uid}"
      done

      mapfile -t remote_managed_uids < <(
        grafana_api_request GET \
          "${grafana_url}/api/search?type=dash-db&tag=${managed_tag}" \
          "${grafana_api_key}" |
          jq -r '.[].uid // empty'
      )

      for uid in "${remote_managed_uids[@]}"; do
        if [[ ! " ${desired_uids[*]} " =~ [[:space:]]${uid}[[:space:]] ]]; then
          grafana_api_request DELETE \
            "${grafana_url}/api/dashboards/uid/${uid}" \
            "${grafana_api_key}" >/dev/null
          echo "Deleted stale ${uid}"
        fi
      done
      ;;
    export)
      local uid="${1:-}"
      local target_file response body
      if [[ -z "$uid" ]]; then
        print_grafana_dashboards_help >&2
        exit 1
      fi

      target_file=$(find "$dashboards_dir" -maxdepth 1 -type f -name '*.json' -print0 | \
        while IFS= read -r -d '' file; do
          if [[ "$(jq -r '.uid // empty' "$file")" == "$uid" ]]; then
            printf '%s\n' "$file"
            break
          fi
        done)

      if [[ -z "$target_file" ]]; then
        echo "Error: no checked-in dashboard JSON with uid '$uid' under $dashboards_dir." >&2
        exit 1
      fi

      response=$(grafana_api_request GET \
        "${grafana_url}/api/dashboards/uid/${uid}" \
        "${grafana_api_key}")
      body=$(printf '%s\n' "$response" | jq '.dashboard | del(.id, .version)')
      printf '%s\n' "$body" > "$target_file"
      echo "Exported ${uid} -> ${target_file}"
      ;;
    *)
      echo "Error: Unknown grafana dashboards action '$action'" >&2
      print_grafana_dashboards_help >&2
      exit 1
      ;;
  esac
}

cmd_grafana() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    -h|--help)
      print_grafana_help
      ;;
    "")
      echo "Error: Missing grafana subcommand" >&2
      print_grafana_help >&2
      exit 1
      ;;
    dashboards)
      cmd_grafana_dashboards "$@"
      ;;
    *)
      echo "Error: Unknown grafana subcommand '$subcommand'" >&2
      print_grafana_help >&2
      exit 1
      ;;
  esac
}

# --- Build host table from hosts.nix ---
build_host_table() {
  local hosts_nix="$1"
  local current_hostname
  current_hostname=$(hostname)

  local all_hosts
  all_hosts=$(nix eval -f "$hosts_nix" --json --apply 'builtins.attrNames' 2>/dev/null) || return 0
  local host_list
  host_list=$(echo "$all_hosts" | jq -r '.[]')

  echo "| Host | Hostname | Role | SSH Target | Fallback IP | Build Remote |"
  echo "|------|----------|------|------------|-------------|--------------|"
  for host in $host_list; do
    local host_json hostname role ssh_target fallback_ip build_on_remote marker
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    hostname=$(echo "$host_json" | jq -r '.hostname // ""')
    role=$(echo "$host_json" | jq -r '.role // ""')
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // ""')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // ""')
    build_on_remote=$(echo "$host_json" | jq -r '.buildOnRemote // false')
    marker=""
    [[ "$hostname" == "$current_hostname" ]] && marker=" ← current"
    echo "| $host$marker | $hostname | $role | ${ssh_target:-—} | ${fallback_ip:-—} | $build_on_remote |"
  done
}

# --- Build user/agent table from nixos-config flake ---
# Evaluates keystone.os.users and keystone.os.agents for the given host.
# Prints nothing on failure or timeout (graceful degradation).
# NOTE: First-call may take 30-60s on a cold Nix eval cache; subsequent calls
# are fast due to Nix's built-in evaluation cache.
build_user_table() {
  local repo_root="$1"
  local current_host="$2"

  [[ -z "$current_host" ]] && return 0

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local users_json agents_json
  users_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${current_host}.config.keystone.os.users" \
    --json \
    --apply 'u: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; }) u' \
    "${override_args[@]}" \
    2>/dev/null) || users_json=""
  agents_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${current_host}.config.keystone.os.agents" \
    --json \
    --apply 'a: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; email = v.email or ""; host = v.host or ""; }) a' \
    "${override_args[@]}" \
    2>/dev/null) || agents_json=""

  [[ -z "$users_json" && -z "$agents_json" ]] && return 0

  echo "| Name | Type | Full Name | Email | Host |"
  echo "|------|------|-----------|-------|------|"
  if [[ -n "$users_json" ]]; then
    echo "$users_json" | jq -r 'to_entries[] | "| \(.key) | user | \(.value.fullName) | | |"'
  fi
  if [[ -n "$agents_json" ]]; then
    echo "$agents_json" | jq -r 'to_entries[] | "| \(.key) | agent | \(.value.fullName) | \(.value.email) | \(.value.host) |"'
  fi
}

# --- ks update workflow documentation (REQ-014.5) ---
# NOTE: ks update/switch requires sudo. Agents MUST NOT run it directly.
# This documentation is injected as reference knowledge so the agent can
# explain the workflow to humans or understand the deploy pipeline.
ks_update_workflow_docs() {
  cat <<'WFDOC'
## Deployment Workflows (Reference Only — requires sudo, human-only)

> **WARNING**: `ks update` and `ks switch` call `sudo` and activate system
> configurations. Agents MUST NOT run these commands. Use `ks build` to test
> changes, then ask a human to deploy.

### 1. `ks update` — Full Release Workflow
`ks update [--debug] [--dev] [--boot] [--pull] [--lock] [HOSTS]`

Use this for official updates. It ensures everything is pulled, locked,
verified, and pushed to origin before deployment.

1. **Pull** nixos-config and all registered repos
2. **Verify** all repos are clean
3. **Lock** flake inputs and **Commit** flake.lock
4. **Build** all target hosts in parallel for verification
5. **Push** nixos-config to origin
6. **Deploy** hosts sequentially using the verified store paths (fast activation)

### 2. `ks switch` — Fast Iteration Workflow
`ks switch [--boot] [HOSTS]`

Use this for local development. It builds and activates the current state of
the local repo immediately, skipping pull, lock, and push phases.

### Flags (update)

| Flag | Effect |
|------|--------|
| `--debug` | Show warning lines from underlying `git`/`nix` commands |
| `--dev` | Build and deploy the current unlocked checkout, skipping pull, lock, and push |
| `--boot` | Use `boot` instead of `switch` mode (reboot required to apply) |
| `--pull` | Pull repos only — no build or deploy |
| `--lock` | Force locking (default when `--dev` is not set), full system rebuild |

### HOSTS

Comma-separated list of host names (e.g. `ocean,maia`). Defaults to current hostname.
Risky hosts should be placed last: `workstation,ocean`.
WFDOC
}

# --- Local flake override documentation (REQ-014.7) ---
local_flake_override_docs() {
  cat <<'OFDOC'
## Local Flake Overrides

`ks` auto-detects local repo clones and passes
`--override-input` flags to every `nix build` / `ks switch` call —
no manual flags needed.

### Detected Paths (in order)

| Input | Paths checked |
|-------|---------------|
| <input> | `~/.keystone/repos/<owner>/<repo>`, `<repo>/.repos/<name>`, `<repo>/.submodules/<name>` |

### Workflow for Repo Changes

1. Edit files in local repo checkout
2. Test with `ks build --dev` (builds home-manager with local overrides)
3. Apply locally with `ks switch` (system update with local overrides)
4. Once satisfied, commit + push the repo
5. Run `ks update` for official deployment (locks and pushes nixos-config)
OFDOC
}

# --- Fleet health: check reachability + NixOS generation for all hosts ---
gather_fleet_health() {
  local hosts_nix="$1"
  local local_gen="$2"
  local current_hostname
  current_hostname=$(hostname)

  local all_hosts
  all_hosts=$(nix eval -f "$hosts_nix" --json --apply 'builtins.attrNames' 2>/dev/null) || return 0
  local host_list
  host_list=$(echo "$all_hosts" | jq -r '.[]')

  echo "### Fleet status"
  echo "| Host | Reachable | NixOS Generation | Status |"
  echo "|------|-----------|------------------|--------|"

  for host in $host_list; do
    local host_json hostname ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    hostname=$(echo "$host_json" | jq -r '.hostname // ""')
    ssh_target=$(resolve_ssh_target "$repo_root" "$host" "$host_json")
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // ""')

    # Current host — use local data
    if [[ "$hostname" == "$current_hostname" ]]; then
      echo "| $host | local | $local_gen | ← current |"
      continue
    fi

    # Skip hosts with no SSH target
    if [[ -z "$ssh_target" ]]; then
      echo "| $host | — | — | no sshTarget |"
      continue
    fi

    # Try SSH with Tailscale → fallback
    local resolved="$ssh_target"
    local reachable="no"
    local remote_gen="—"
    local status="unreachable"

    if ks_ssh_test "$ssh_target"; then
      reachable="yes"
    elif [[ -n "$fallback_ip" ]] && ks_ssh_test "$fallback_ip"; then
      reachable="yes (LAN)"
      resolved="$fallback_ip"
    fi

    if [[ "$reachable" != "no" ]]; then
      remote_gen=$(ks_ssh "$resolved" nixos-version 2>/dev/null || echo "unknown")
      if [[ "$remote_gen" == "$local_gen" ]]; then
        status="ok"
      elif [[ "$remote_gen" == "unknown" ]]; then
        status="unknown"
      else
        status="drift"
      fi
    fi

    echo "| $host | $reachable | $remote_gen | $status |"
  done
}

# --- Agent health: check key systemd services for each agent ---
gather_agent_health() {
  local hosts_nix="$1"

  # Check if agentctl is available
  if ! command -v agentctl >/dev/null 2>&1; then
    echo "### Agent status"
    echo "_agentctl not available on this host_"
    return 0
  fi

  local agents
  agents=$(known_agents_list 2>/dev/null || true)
  if [[ -z "$agents" ]]; then
    echo "### Agent status"
    echo "_No agents configured_"
    return 0
  fi

  echo "### Agent status"
  echo "| Agent | Task Loop | Notes Sync | SSH Agent | Status |"
  echo "|-------|-----------|------------|-----------|--------|"

  local agent
  while IFS= read -r agent; do
    [[ -n "$agent" ]] || continue
    local task_loop notes_sync ssh_agent overall

    # Check key services via agentctl (handles remote dispatch automatically)
    task_loop=$(safe_systemctl_state "$agent" "agent-${agent}-task-loop.timer")
    notes_sync=$(safe_systemctl_state "$agent" "agent-${agent}-notes-sync.timer")
    ssh_agent=$(safe_systemctl_state "$agent" "agent-${agent}-ssh-agent.service")

    # Determine overall status
    if [[ "$task_loop" == "active" && "$notes_sync" == "active" && "$ssh_agent" == "active" ]]; then
      overall="ok"
    elif [[ "$task_loop" == "unknown" && "$notes_sync" == "unknown" ]]; then
      overall="unreachable"
    else
      overall="degraded"
    fi

    echo "| $agent | $task_loop | $notes_sync | $ssh_agent | $overall |"
  done <<< "$agents"
}

# --- Agent task queue: count tasks by status ---
gather_agent_tasks() {
  # Check if agentctl is available
  if ! command -v agentctl >/dev/null 2>&1; then
    return 0
  fi

  local agents
  agents=$(known_agents_list 2>/dev/null || true)
  [[ -z "$agents" ]] && return 0

  echo "### Agent tasks"
  echo "| Agent | Pending | In Progress | Blocked | Completed |"
  echo "|-------|---------|-------------|---------|-----------|"

  local agent
  while IFS= read -r agent; do
    [[ -n "$agent" ]] || continue
    local tasks_yaml pending in_progress blocked completed
    tasks_yaml=$(agentctl "$agent" exec cat "/home/agent-${agent}/notes/TASKS.yaml" 2>/dev/null || true)

    if [[ -z "$tasks_yaml" ]]; then
      echo "| $agent | — | — | — | — |"
      continue
    fi

    pending=$(count_status_matches "$tasks_yaml" "pending")
    in_progress=$(count_status_matches "$tasks_yaml" "in_progress")
    blocked=$(count_status_matches "$tasks_yaml" "blocked")
    completed=$(count_status_matches "$tasks_yaml" "completed")

    echo "| $agent | $pending | $in_progress | $blocked | $completed |"
  done <<< "$agents"
}

# --- Gather current system state (for ks doctor) ---
gather_system_state() {
  local repo_root="$1"
  local hosts_nix="$2"
  local current_host="${3:-}"

  doctor_progress "collecting local system state"
  echo "## System State"
  echo ""

  # NixOS generation
  local gen=""
  if command -v nixos-version >/dev/null 2>&1; then
    gen=$(nixos-version 2>/dev/null || true)
  fi
  [[ -n "$gen" ]] && echo "**NixOS generation**: $gen"
  echo ""

  # Systemd failed units
  echo "### Failed systemd units"
  local failed=""
  failed=$(failed_units_list)
  if [[ -z "$failed" ]]; then
    echo "_None_"
  else
    while IFS= read -r unit; do
      echo "- $unit"
    done <<< "$failed"
  fi
  echo ""

  # Disk usage
  echo "### Disk usage"
  echo '```'
  df -h 2>/dev/null | head -20 || echo "_unavailable_"
  echo '```'
  echo ""

  # Flake lock age
  echo "### flake.lock age"
  if [[ -f "$repo_root/flake.lock" ]]; then
    local lock_age
    lock_age=$(git -C "$repo_root" log -1 --format="%ar" -- flake.lock 2>/dev/null || true)
    if [[ -n "$lock_age" ]]; then
      echo "_Last updated: ${lock_age}_"
    else
      echo "_unknown_"
    fi
  else
    echo "_flake.lock not found_"
  fi
  echo ""

  # Ollama diagnostics
  doctor_progress "checking Ollama diagnostics"
  gather_ollama_diagnostics "$repo_root" "$current_host"
  echo ""

  # Fleet health (host reachability + generation comparison)
  if [[ -n "$hosts_nix" && -f "$hosts_nix" ]]; then
    doctor_progress "checking fleet health"
    gather_fleet_health "$hosts_nix" "$gen"
    echo ""
  fi

  # Agent health (service status)
  doctor_progress "checking agent health"
  gather_agent_health "$hosts_nix"
  echo ""

  # Agent task queue
  doctor_progress "checking agent tasks"
  gather_agent_tasks
}

gather_ollama_diagnostics() {
  local repo_root="$1"
  local current_host="$2"
  local host="${OLLAMA_HOST:-}"

  echo "### Ollama diagnostics"

  if [[ -n "$host" ]]; then
    echo "- API endpoint: $host"
    echo "- Available models:"
    list_ollama_models "$host"
    return
  fi

  if [[ -z "$current_host" ]]; then
    echo "- API endpoint: _unavailable_"
    echo "- Available models:"
    echo "  - _current host is not defined in hosts.nix_"
    return
  fi

  local user
  user=$(resolve_current_hm_user "$repo_root" "$current_host")
  if [[ -z "$user" ]]; then
    echo "- API endpoint: _unavailable_"
    echo "- Available models:"
    echo "  - _no home-manager user found for current host_"
    return
  fi

  host=$(resolve_ollama_host "$repo_root" "$current_host" "$user")
  echo "- API endpoint: ${host:-_not configured_}"

  echo "- Available models:"
  list_ollama_models "$host"
}

# --- Build shared agent system prompt (REQ-014.2-8) ---
# Usage: build_agent_prompt repo_root hosts_nix ks_repo current_host
build_agent_prompt() {
  local repo_root="$1"
  local hosts_nix="$2"
  local ks_repo="$3"
  local current_host="$4"

  local prompt=""

  # 1. Static conventions. Prefer the generated canonical per-user context at
  # ~/.keystone/AGENTS.md. Fall back to repo conventions for pre-activation or
  # ad-hoc checkout usage.
  local canonical_prompt="$HOME/.keystone/AGENTS.md"
  if [[ -f "$canonical_prompt" ]]; then
    prompt="$(cat "$canonical_prompt")"
  elif [[ -n "$ks_repo" ]]; then
    local conventions
    conventions=$(load_conventions "$ks_repo")
    if [[ -n "$conventions" ]]; then
      prompt="$conventions"
    fi
  fi

  if [[ -n "$ks_repo" ]]; then
    # Load ks-agent archetype (provides identity and constraints for ks agent sessions)
    local archetype_file="$ks_repo/modules/os/agents/archetypes/ks-agent.md"
    if [[ -f "$archetype_file" ]]; then
      if [[ -n "$prompt" ]]; then
        prompt="$prompt

---

$(cat "$archetype_file")"
      else
        prompt="$(cat "$archetype_file")"
      fi
    fi
  fi

  # 2. ks update workflow (REQ-014.5)
  local workflow
  workflow=$(ks_update_workflow_docs)
  if [[ -n "$prompt" ]]; then
    prompt="$prompt

---

$workflow"
  else
    prompt="$workflow"
  fi

  # 3. Local flake override docs (REQ-014.7)
  local override_docs
  override_docs=$(local_flake_override_docs)
  prompt="$prompt

---

$override_docs"

  # 4. Current host identity (REQ-014.4)
  local current_hostname
  current_hostname=$(hostname)
  local nixos_gen=""
  if command -v nixos-version >/dev/null 2>&1; then
    nixos_gen=$(nixos-version 2>/dev/null || true)
  fi
  local host_section
  host_section="## Current Host

- **Hostname**: $current_hostname"
  [[ -n "$nixos_gen" ]] && host_section="$host_section
- **NixOS generation**: $nixos_gen"
  prompt="$prompt

---

$host_section"

  # 5. Host table (REQ-014.2, REQ-014.17-19)
  local host_table
  host_table=$(build_host_table "$hosts_nix")
  if [[ -n "$host_table" ]]; then
    prompt="$prompt

## Hosts

$host_table"
  fi

  # 6. Users/agents table (REQ-014.3) — best-effort, skipped on cold cache timeout
  local user_table
  user_table=$(build_user_table "$repo_root" "$current_host")
  if [[ -n "$user_table" ]]; then
    prompt="$prompt

## Users & Agents

$user_table"
  fi

  # 7. Dev mode status (REQ-016.11-13)
  local ks_dev_path
  ks_dev_path=$(find_local_repo "$repo_root" "ncrmro/keystone")
  if [[ -n "$ks_dev_path" ]]; then
    local ks_branch ks_dirty=""
    ks_branch=$(git -C "$ks_dev_path" branch --show-current 2>/dev/null || echo "unknown")
    if ! git -C "$ks_dev_path" diff --quiet 2>/dev/null || ! git -C "$ks_dev_path" diff --cached --quiet 2>/dev/null; then
      ks_dirty=" (has uncommitted changes)"
    fi
    prompt="$prompt

---

## Development Mode

**Status**: Active — using local keystone from disk${ks_dirty}
**Path**: $ks_dev_path
**Branch**: $ks_branch

### Dev Mode Conventions

- \`ks build\`: Rebuilds **home-manager profiles only** (users + agents).
- \`ks update --dev\` / \`ks switch\`: Deploy the **current unlocked checkout** to the selected hosts, skipping pull, lock, and push.
- \`ks build --lock\` / \`ks update\` (default): **Full NixOS system rebuild**. Pushes keystone (forks if not a collaborator), locks flake inputs, builds, pushes nixos-config, deploys.
- Changes to keystone are NOT locked into flake.lock until \`--lock\` is used.
- When ready to lock: commit + push keystone, then run \`ks update\` (or \`ks build --lock\`)."
  fi

  printf '%s' "$prompt"
}

# --- Launch AI agent with system prompt ---
# Writes prompt to a checksummed temp file and passes it via @file
# reference in --append-system-prompt. This avoids Linux MAX_ARG_STRLEN
# (128KB per argument) — the argv only contains the small @path string,
# while claude reads the full prompt from disk.
# Usage: launch_agent local_model prompt [passthrough args...]
launch_agent() {
  local local_model="$1"; shift
  local repo_root="$1"; shift
  local current_host="$1"; shift
  local prompt="$1"; shift

  local prompt_file
  prompt_file="/tmp/ks-prompt-$(printf '%s' "$prompt" | md5sum | cut -d' ' -f1).md"
  printf '%s' "$prompt" > "$prompt_file"
  trap 'rm -f "$prompt_file"' EXIT

  if [[ -n "$local_model" ]]; then
    if [[ -z "$current_host" ]]; then
      echo "Error: could not resolve the current host in hosts.nix, so --local cannot load home-manager Ollama settings." >&2
      exit 1
    fi
    local hm_user ollama_host default_model resolved_model
    hm_user=$(resolve_current_hm_user "$repo_root" "$current_host")
    require_ollama_enabled "$repo_root" "$current_host" "$hm_user"
    ollama_host=$(resolve_ollama_host "$repo_root" "$current_host" "$hm_user")
    default_model=$(resolve_ollama_default_model "$repo_root" "$current_host" "$hm_user")
    resolved_model=$(resolve_local_model "$local_model" "$default_model")

    if ! command -v ollama >/dev/null 2>&1; then
      echo "Error: --local requires ollama to be installed." >&2
      exit 1
    fi
    if ! command -v claude >/dev/null 2>&1; then
      echo "Error: --local requires claude to be installed." >&2
      exit 1
    fi

    ANTHROPIC_BASE_URL="$ollama_host" \
    ANTHROPIC_AUTH_TOKEN="ollama" \
      exec claude --model "$resolved_model" --append-system-prompt "@${prompt_file}" "$@"
  elif command -v claude >/dev/null 2>&1; then
    exec claude --append-system-prompt "@${prompt_file}" "$@"
  else
    echo "Error: claude is not available." >&2
    exit 1
  fi
}

cmd_agent() {
  local local_model=""
  local passthrough_args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_agent_help
        return 0
        ;;
      --local)
        shift
        if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
          local_model="$1"; shift
        else
          local_model="default"
        fi
        ;;
      *) passthrough_args+=("$1"); shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"
  local ks_repo
  ks_repo=$(find_keystone_repo "$repo_root")

  # Resolve current host key in hosts.nix for user table eval (REQ-014.3)
  local current_hostname current_host=""
  current_hostname=$(hostname)
  current_host=$(nix eval -f "$hosts_nix" --raw \
    --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current_hostname\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m" \
    2>/dev/null) || current_host=""

  local prompt
  prompt=$(build_agent_prompt "$repo_root" "$hosts_nix" "$ks_repo" "$current_host")

  launch_agent "$local_model" "$repo_root" "$current_host" "$prompt" "${passthrough_args[@]+"${passthrough_args[@]}"}"
}

cmd_print() {
  local input_file=""
  local output_file=""
  local open_after=false
  local no_print=false
  local print_css_path="@KS_PRINT_CSS@"

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_print_help
        return 0
        ;;
      -o|--output)
        shift
        output_file="$1"
        shift
        ;;
      --open)
        open_after=true
        shift
        ;;
      --preview)
        open_after=true
        no_print=true
        shift
        ;;
      --no-print)
        no_print=true
        shift
        ;;
      -*)
        echo "Error: Unknown option '$1'" >&2
        print_print_help >&2
        return 1
        ;;
      *)
        if [[ -z "$input_file" ]]; then
          input_file="$1"
        else
          echo "Error: Unexpected argument '$1'" >&2
          print_print_help >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$input_file" ]]; then
    echo "Error: No input file specified." >&2
    print_print_help >&2
    return 1
  fi

  if [[ ! -f "$input_file" ]]; then
    echo "Error: File not found: $input_file" >&2
    return 1
  fi

  if [[ -z "$output_file" ]]; then
    output_file="${input_file%.md}.pdf"
    if [[ "$output_file" == "$input_file" ]]; then
      output_file="${input_file}.pdf"
    fi
  fi

  if [[ "$print_css_path" == "@KS_PRINT_CSS@" ]]; then
    # Dev mode links this script from the live checkout, so build-time placeholder
    # substitution does not run. Resolve the adjacent stylesheet from disk instead.
    local script_dir=""
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    print_css_path="${script_dir}/print.css"
  fi

  if [[ ! -f "$print_css_path" ]]; then
    echo "Error: Print stylesheet not found: $print_css_path" >&2
    return 1
  fi

  # Select PDF engine — prefer weasyprint, fall back to wkhtmltopdf then LaTeX
  local engine=""
  if command -v weasyprint &>/dev/null; then
    engine="weasyprint"
  elif command -v wkhtmltopdf &>/dev/null; then
    engine="wkhtmltopdf"
  elif command -v pdflatex &>/dev/null; then
    engine="pdflatex"
  elif command -v xelatex &>/dev/null; then
    engine="xelatex"
  else
    echo "Error: No PDF engine found. Install weasyprint, wkhtmltopdf, or a LaTeX distribution." >&2
    return 1
  fi

  local pandoc_args=(
    "$input_file"
    --standalone
    --pdf-engine="$engine"
    --css="$print_css_path"
    -V colorlinks=false
    -o "$output_file"
  )

  pandoc "${pandoc_args[@]}"
  echo "✓  PDF written: $output_file"

  if [[ "$open_after" == true ]]; then
    xdg-open "$output_file" &
  fi

  # Auto-send to default CUPS printer unless --no-print was specified
  if [[ "$no_print" == false ]] && command -v lpstat &>/dev/null; then
    local default_printer=""
    default_printer=$(lpstat -d 2>/dev/null | awk '/system default destination:/ {print $NF}')
    if [[ -n "$default_printer" ]]; then
      lp "$output_file" >/dev/null
      echo "✓  Sent to printer: $default_printer"
    fi
  fi
}

cmd_doctor() {
  local local_model=""
  local full_mode=false
  local passthrough_args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_doctor_help
        return 0
        ;;
      --full)
        full_mode=true
        shift
        ;;
      --local)
        shift
        if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
          local_model="$1"; shift
        else
          local_model="default"
        fi
        ;;
      *) passthrough_args+=("$1"); shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"

  local current_hostname current_host=""
  doctor_progress "resolving current host"
  current_hostname=$(hostname)
  current_host=$(nix eval -f "$hosts_nix" --raw \
    --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current_hostname\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m" \
    2>/dev/null) || current_host=""

  local report_file=""
  if [[ -t 1 ]] && command -v glow >/dev/null 2>&1; then
    report_file=$(mktemp "${TMPDIR:-/tmp}/ks-doctor.XXXXXX.md")
    doctor_progress "building report"
    gather_system_state "$repo_root" "$hosts_nix" "$current_host" > "$report_file"
    doctor_progress "rendering report"
    glow "$report_file"
    rm -f "$report_file"
  else
    gather_system_state "$repo_root" "$hosts_nix" "$current_host"
  fi

  # --full: run E2E agent lifecycle test after the standard report
  if [[ "$full_mode" == true ]]; then
    doctor_progress "running E2E agent lifecycle test"
    cmd_agents_e2e "${passthrough_args[@]}" || true
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    return 0
  fi

  printf '\nLaunch the default agent to review this doctor report? [y/N] '
  local launch_reply=""
  IFS= read -r launch_reply || true
  case "$launch_reply" in
    y|Y|yes|YES)
      cmd_agent ${local_model:+"--local"} ${local_model:+"$local_model"} "${passthrough_args[@]}"
      ;;
    *)
      return 0
      ;;
  esac
}

# --- Main dispatch ---
if [[ $# -lt 1 ]]; then
  print_main_help >&2
  exit 1
fi

CMD="$1"; shift
case "$CMD" in
  -h|--help)
    print_main_help
    ;;
  help)
    show_help_topic "$@"
    ;;
  approve) cmd_approve "$@" ;;
  agents) cmd_agents "$@" ;;
  build)  cmd_build "$@" ;;
  docs)   cmd_docs "$@" ;;
  photos) cmd_photos "$@" ;;
  grafana) cmd_grafana "$@" ;;
  sync-agent-assets) cmd_sync_agent_assets "$@" ;;
  update) cmd_update "$@" ;;
  switch) cmd_switch "$@" ;;
  install) cmd_install "$@" ;;
  sync-host-keys) cmd_sync_host_keys "$@" ;;
  print)  cmd_print "$@" ;;
  agent)  cmd_agent "$@" ;;
  doctor) cmd_doctor "$@" ;;
  *)
    echo "Error: Unknown command '$CMD'" >&2
    echo "Known commands: help, approve, build, update, switch, install, agents, docs, photos, sync-agent-assets, sync-host-keys, grafana, print, agent, doctor" >&2
    exit 1
    ;;
esac
