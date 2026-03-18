---
layout: default
title: OS Agents
---

# OS Agents (`keystone.os.agents`)

OS agents are non-interactive NixOS user accounts designed for autonomous LLM-driven operation. Each agent gets an isolated home directory, SSH keys, mail, browser, and optional workspace cloning.

## Quick Start

```nix
keystone.os.agents.drago = {
  fullName = "Drago";
  email = "drago@example.com";
  ssh.publicKey = "ssh-ed25519 AAAAC3... agent-drago";
  space.repo = "ssh://forgejo@git.example.com:2222/drago/agent-space.git";
};
```

## Agent Space (Workspace Cloning)

The `space.repo` option clones a git repository into `/home/agent-{name}/agent-space/` on first boot.

### Forgejo SSH URL Format

When using Forgejo's built-in SSH server, the SSH username must match the system user running Forgejo — typically `forgejo`, **not** `git`.

```
# CORRECT — Forgejo built-in SSH server
ssh://forgejo@git.example.com:2222/owner/repo.git

# WRONG — will fail with "Permission denied (publickey)"
ssh://git@git.example.com:2222/owner/repo.git
git@git.example.com:owner/repo.git
```

The `git@` convention is GitHub/GitLab-specific. Forgejo's built-in SSH server (`START_SSH_SERVER = true`) runs as the `forgejo` user and only accepts connections with that username.

If using Forgejo with OpenSSH (passthrough mode) instead of the built-in server, `git@` may work depending on configuration — but the built-in server always requires `forgejo@`.

### SSH Authentication

The clone service uses the agent's agenix SSH key directly (`/run/agenix/agent-{name}-ssh-key`). The key must be registered in the Forgejo user's SSH keys settings.

### Required Agenix Secrets

Each agent with SSH configured needs:
- `agent-{name}-ssh-key` — Private SSH key (ed25519)
- `agent-{name}-ssh-passphrase` — Passphrase for the key

### Retry Behavior

The clone service retries on failure (up to 10 attempts over 10 minutes with 30-second intervals). Check status with:

```bash
systemctl status clone-agent-space-{name}.service
journalctl -xeu clone-agent-space-{name}.service
```

## What Each Agent Gets

| Feature | Service/Config | Details |
|---------|---------------|---------|
| User account | `agent-{name}` | UID 4001+, group `agents`, no sudo |
| Home directory | `/home/agent-{name}` | chmod 750, readable by `agent-admins` group |
| SSH agent | `agent-{name}-ssh-agent.service` | Auto-loads agenix key with passphrase |
| Git signing | `agent-{name}-git-config.service` | SSH-based commit signing |
| Desktop | `agent-{name}-labwc.service` | Headless Wayland (labwc + wayvnc) |
| Browser | `agent-{name}-chromium.service` | Chromium with remote debugging |
| Mail | himalaya CLI | Stalwart IMAP/SMTP via agenix password |
| Calendar | calendula CLI | Stalwart CalDAV (auto-configured from mail) |
| Contacts | cardamum CLI | Stalwart CardDAV (auto-configured from mail) |
| Bitwarden | `bw` CLI | Configured for Vaultwarden instance |
| Workspace | `clone-agent-space-{name}.service` | Clones `space.repo` on first boot |

## Debugging

### Clone fails with "Permission denied (publickey)"

1. **Check the SSH username** in `space.repo` — must be `forgejo@` for Forgejo's built-in SSH server
2. **Verify the key is registered** in Forgejo under the correct user's SSH keys
3. **Test manually:**
   ```bash
   sudo runuser -u agent-{name} -- ssh -vvv \
     -i /run/agenix/agent-{name}-ssh-key \
     -o StrictHostKeyChecking=accept-new \
     -o IdentitiesOnly=yes \
     -p 2222 -T forgejo@git.example.com
   ```
4. **Check key fingerprint matches:**
   ```bash
   # Fingerprint of the agenix private key
   ssh-keygen -lf /run/agenix/agent-{name}-ssh-key

   # Compare with the public key in your config
   echo "ssh-ed25519 AAAAC3..." | ssh-keygen -lf -
   ```

### Service dependency order

The clone service depends on:
- `agent-homes.service` (or `zfs-agent-datasets.service` on ZFS)

The SSH agent service runs independently and is not a dependency of the clone service.

## Agent-Space Repository Structure

The agent-space is the agent's primary working directory. It can be provisioned in two modes:

- **Clone mode** (`space.repo`): Clone an existing repository
- **Scaffold mode** (default): Create a new agent-space with standard files

### Standard Directory Layout

```
/home/agent-{name}/agent-space/
├── AGENTS.md                    # Operational conventions, uses {name}/{email} placeholders
├── CLAUDE.md -> AGENTS.md       # Symlink (same file, NOT separate)
├── ARCHITECTURE.md              # System architecture the agent operates within
├── HUMAN.md                     # Human operator: name, email
├── REQUIREMENTS.md              # Standing requirements and constraints
├── SERVICES.md                  # Intranet services table (Service, URL)
├── SOUL.md                      # Agent identity: name, email, accounts table
├── ISSUES.yaml                  # Known issues and incident log
├── PROJECTS.yaml                # Project priority list with source definitions
├── SCHEDULES.yaml               # Recurring task definitions
├── TASKS.yaml                   # Current task queue
├── .envrc                       # direnv: `use flake`
├── .mcp.json                    # MCP server configuration
├── flake.nix                    # Dev shell with required tools
├── flake.lock
│
├── bin/                         # Agent-local scripts
│   ├── agent.coding-agent       # Coding subagent orchestrator (from Nix package)
│   ├── fetch-email-source       # Email-to-JSON bridge (from Nix package)
│   └── claude_tasks             # Manual task trigger wrapper
│
├── .repos/                      # Cloned repositories ({owner}/{repo})
├── logs/                        # Task execution logs
│   └── tasks/                   # Per-task logs ({timestamp}_{task-name}.log)
│
├── .deepwork/
│   ├── config.yml
│   └── jobs/
│       ├── task_loop/           # Autonomous work orchestration
│       ├── cronjobs/            # Cronjob self-management
│       ├── daily_status/        # Status reporting
│       └── research/            # Structured research
│
├── .cronjobs/
│   ├── shared/
│   │   ├── lib.sh               # Shared functions (logging, locking)
│   │   ├── config.sh            # Environment variables and paths
│   │   └── setup.sh             # Installs units into ~/.config/systemd/user/
│   └── {job-name}/
│       ├── run.sh               # Job execution script
│       ├── service.unit         # Systemd service template
│       └── timer.unit           # Systemd timer template
│
└── .claude/
    └── settings.json            # Claude Code permissions allowlist
```

### Identity Documents

**SOUL.md** — Agent identity, auto-populated from NixOS config:

```markdown
# Soul

**Name:** Kumquat Drago
**Goes by:** Drago
**Email:** drago@example.com

## Accounts

| Service | Host | Username | Auth Method | Credentials |
|---------|------|----------|-------------|-------------|
| GitHub  | github.com | kdrgo | OAuth device flow | `~/.config/gh/hosts.yml` |
| Forgejo | git.example.com | drago | API token | fj keyfile |
```

**HUMAN.md** — Human operator info:

```markdown
# Human

**Name:** Nicholas Romero
**Email:** nicholas.romero@example.com
```

**AGENTS.md** — Operational conventions. Uses `{name}` and `{email}` placeholders (account-specific values live in `SOUL.md`). `CLAUDE.md` is a symlink to this file.

## Task Loop Architecture

The task loop uses a two-timer pipeline for autonomous work orchestration.

### Two-Timer Design

```
                    ┌─────────────────────────────────────────────┐
                    │              Systemd Timers                  │
                    │                                             │
  5 AM daily ───▶   │  agent-scheduler.timer                      │
                    │    └── agent-scheduler.service               │
                    │        └── Creates tasks from SCHEDULES.yaml │
                    │           + triggers task-loop               │
                    │                                             │
  Every 5 min ──▶   │  agent-task-loop.timer                      │
                    │    └── agent-task-loop.service               │
                    │        └── Runs agent-space/run.sh           │
                    └─────────────────────────────────────────────┘
```

### Pipeline Data Flow

```
run.sh Pipeline:

1. PRE-FETCH         ──▶  PROJECTS.yaml sources → shell commands → JSON
2. HASH CHECK        ──▶  Compare JSON hash → skip ingest if unchanged
3. INGEST  (haiku)   ──▶  Parse source JSON → update TASKS.yaml
4. PRIORITIZE (haiku) ──▶  Reorder TASKS.yaml by PROJECTS.yaml priority + assign model
5. EXECUTE LOOP       ──▶  For each pending task:
   │                        ├── Check `needs` dependencies (yq+jq)
   │                        ├── Read task model/workflow
   │                        ├── Launch LLM session (model per task)
   │                        └── Log to logs/tasks/{timestamp}_{name}.log
   │
   └── Stop conditions: max tasks, max wall time, error threshold
```

### Model Separation Strategy

| Step | Default Model | Rationale |
|------|--------------|-----------|
| Ingest | haiku | Fast parsing, no reasoning needed |
| Prioritize | haiku | Simple reordering, cost-efficient |
| Execute | sonnet (per-task override) | Reasoning-heavy, model matches task complexity |

Tasks can override the execute model via the `model` field in TASKS.yaml. Complex tasks use `opus`, simple tasks use `haiku`.

### Key Design Decision: run.sh in Agent-Space

The `run.sh` script lives in the agent-space directory (not the Nix store). This allows the agent to modify its own pipeline behavior — adding new source fetchers, adjusting stop conditions, or changing the ingest/prioritize flow without requiring a NixOS rebuild.

## YAML Schema Reference

### TASKS.yaml

```yaml
tasks:                             # REQUIRED: only top-level key
  - name: "task-name"              # REQUIRED: kebab-case identifier
    description: "What to do"      # REQUIRED: human-readable
    status: pending                # REQUIRED: pending|in_progress|completed|blocked
    project: "project-name"       # MAY: from PROJECTS.yaml
    source: "email"               # MAY: email|github-issue|github-pr|schedule|manual
    source_ref: "email-42-u@h"    # MAY: unique ID for deduplication
    model: "sonnet"               # MAY: haiku|sonnet|opus — execution model override
    workflow: "job/workflow"       # MAY: DeepWork workflow to invoke
    needs: ["other-task"]         # MAY: task names that must complete first
    blocked_reason: "..."         # MAY: explanation when status is blocked
```

**Rules:**
1. Valid YAML, single top-level key `tasks` (a sequence)
2. NO other top-level keys (`summary:`, `metadata:`, etc.)
3. Every task MUST have `name`, `description`, `status`
4. Status MUST be one of: `pending`, `in_progress`, `completed`, `blocked`
5. Field names MUST match exactly — no `id`, `priority`, `urgency`, `effort`, `depends_on`
6. Validate after every write: `yq e '.' TASKS.yaml`

**Source ref formats:**
- Email: `email-{id}-{sender_address}`
- GitHub issue: full URL
- Schedule: `schedule-{name}-{YYYY-MM-DD}`

### PROJECTS.yaml

```yaml
projects:
  - name: "project-name"          # REQUIRED: display name
    slug: "project-name"          # REQUIRED: kebab-case
    description: "What it is"     # REQUIRED: human-readable
    status: active                # REQUIRED: active|archived
    priority: 1                   # REQUIRED: numeric (list order = priority)
    updated: "2026-02-15"         # REQUIRED: last updated date
    path: "/home/agent-drago/projects/project-name"  # MAY: working directory for agentctl --project
    repos:                        # MAY: associated repositories
      - "owner/repo-name"

sources:                           # Top-level: pre-fetch source definitions
  - name: "github-issues"         # REQUIRED: identifier
    command: "gh issue list --json number,title,body --assignee @me"  # REQUIRED: outputs JSON
```

### SCHEDULES.yaml

```yaml
schedules:
  - name: "daily-priorities"      # REQUIRED: kebab-case identifier
    description: "..."            # REQUIRED: human-readable
    schedule: "daily"             # REQUIRED: daily | weekly:<day> | monthly:<day>
    workflow: "daily_status/send" # REQUIRED: DeepWork workflow to invoke
```

The scheduler creates tasks with `source: "schedule"` and `source_ref: "schedule-{name}-{YYYY-MM-DD}"` for deduplication.

### ISSUES.yaml

```yaml
issues:
  - name: "issue-name"            # REQUIRED: kebab-case
    description: "What happened"   # REQUIRED: detailed
    discovered_during: "task-name" # REQUIRED: which task surfaced this
    status: open                   # REQUIRED: open|mitigated|resolved
    severity: medium               # MAY: low|medium|high|critical
    workaround: "..."             # MAY: temporary mitigation
    fix: "..."                    # MAY: permanent resolution
```

## Cronjob Convention

Agents manage their own cronjobs via the `.cronjobs/` directory convention.

### Standard Layout

```
.cronjobs/
├── shared/
│   ├── lib.sh           # Logging, error handling, lock management
│   ├── config.sh        # AGENT_SPACE, LOG_DIR, etc.
│   └── setup.sh         # Installs all jobs via symlinks
└── {job-name}/
    ├── run.sh           # Execution script
    ├── service.unit     # systemd service unit
    └── timer.unit       # systemd timer unit
```

### run.sh Template

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../shared/lib.sh"
source "$SCRIPT_DIR/../shared/config.sh"

# Job logic here
log "Starting {job-name}"
# ...
log "Completed {job-name}"
```

**Critical rules:**
- Always use `SCRIPT_DIR` for relative paths, never hardcode absolute paths
- Always source `shared/lib.sh` for logging and error handling
- Capture subprocess exit codes explicitly: `OUTPUT=$(cmd); EXIT_CODE=$?` — do NOT pipe through `tee` (masks exit codes)

### Installation via setup.sh

The `setup.sh` script installs cronjobs by symlinking unit files into the user's systemd directory:

```bash
#!/usr/bin/env bash
SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

for job_dir in "$SCRIPT_DIR"/*/; do
    job_name=$(basename "$job_dir")
    [[ "$job_name" == "shared" ]] && continue

    ln -sf "$job_dir/service.unit" "$SYSTEMD_DIR/${job_name}.service"
    ln -sf "$job_dir/timer.unit" "$SYSTEMD_DIR/${job_name}.timer"
done

systemctl --user daemon-reload
```

### DeepWork Workflows for Cronjobs

The `.deepwork/jobs/cronjobs/` job provides three workflows:
- **create**: Gather requirements → implement job → install via setup.sh
- **edit**: Assess current state → apply changes
- **review**: Collect logs and diagnose → recommend fixes

## DeepWork Job Convention

Each agent-space includes DeepWork job definitions in `.deepwork/jobs/`.

### Required Jobs

| Job | Purpose | Workflows |
|-----|---------|-----------|
| `task_loop` | Autonomous work orchestration | `ingest`, `prioritize`, `run` |
| `cronjobs` | Cronjob self-management | `create`, `edit`, `review` |

### Optional Jobs

| Job | Purpose | Workflows |
|-----|---------|-----------|
| `daily_status` | Status reporting | `send` |
| `research` | Structured research | `research` |

### Job Directory Structure

```
.deepwork/jobs/{job_name}/
├── AGENTS.md          # Job-specific learnings and context
├── job.yml            # Job spec (name, version, workflows, steps)
├── steps/             # One .md file per step
│   └── shared/        # Shared reference docs
├── hooks/             # Custom validation hooks
├── scripts/           # Reusable helper scripts
├── templates/         # Example formats
├── outputs/           # Most recent step outputs
├── instances/         # Current run working directory
└── runs/              # Historical run artifacts
```

### Task Loop Job Workflows

The `task_loop` job has three workflows that map to the pipeline steps:

- **ingest**: `parse_sources` step — Parse pre-fetched JSON, update TASKS.yaml
- **prioritize**: `reorder_tasks` step — Reorder pending tasks by project priority, assign `model` field
- **run**: `execute` + `report` steps — Execute one task, write task report

## Coding Subagent Usage

The `agent.coding-agent` is a bash orchestrator that manages the full lifecycle of a code contribution.

### CLI Interface

```bash
agent.coding-agent \
  --repo OWNER/REPO \
  --task "description of the change" \
  [--branch PREFIX/NAME] \
  [--prefix feature|fix|chore|refactor|docs] \
  [--provider claude|codex|gemini] \
  [--model sonnet|opus] \
  [--max-review-cycles N] \
  [--review-only PR_NUMBER] \
  [--skip-review] \
  [--timeout SECONDS]
```

### Provider Contract

Provider scripts follow a positional argument interface:

```bash
agent.coding-agent.{provider} REPO_DIR SYSTEM_PROMPT_FILE TIMEOUT [--model MODEL]
```

Available providers:
- `agent.coding-agent.claude` — Uses Claude Code CLI with `--dangerously-skip-permissions`
- `agent.coding-agent.codex` — Stub (not yet implemented)
- `agent.coding-agent.gemini` — Stub (not yet implemented)

### Orchestrator/Subagent Split

The bash orchestrator handles all git and platform operations:
1. Pre-flight: verify repo exists in `.repos/`, detect remote type (GitHub/Forgejo), ensure clean state
2. Create branch: `{prefix}/{slugified-task}`
3. Generate system prompt with task context and 7 rules for the agent
4. Run provider: LLM creates commits within the working tree
5. Verify: count commits, check for BLOCKED.md
6. Push: GitHub uses token-based URL, Forgejo uses SSH
7. Create draft PR: `gh pr create --draft` (GitHub), `fj pr create "WIP: ..."` (Forgejo)

The LLM subagent only creates commits — it cannot push, create PRs, or switch branches.

### Review Cycle

After the initial PR, the orchestrator runs up to N review cycles (default 2):

1. Run provider with `sonnet` model and review prompt
2. Provider outputs structured format: `COMMENT: ...` followed by `VERDICT: PASS|FAIL`
3. Comments posted to the PR
4. On `FAIL` (not last cycle): re-run coding agent with fix prompt, push fixes
5. On `PASS`: mark PR ready (`gh pr ready` for GitHub, remove `WIP:` prefix for Forgejo)

## Terminal Environment Requirement

Agent systemd services (`task-loop`, `scheduler`, `notes-sync`) MUST have access to the full home-manager terminal environment. All tools available in an interactive agent shell MUST also be available in systemd service contexts.

### Design

The `notes.nix` module sets each service's PATH to the agent's full home-manager profile:

```
/etc/profiles/per-user/agent-{name}/bin:<nix>/bin:/run/current-system/sw/bin
```

Scripts (`task-loop.sh`, `scheduler.sh`) use bare commands (`yq`, `jq`, `bash`, `git`, `claude`, etc.) that resolve via this PATH. Only config values (`notesDir`, `maxTasks`, `agentName`) are substituted at build time via `pkgs.replaceVars` — tool paths are NOT individually resolved.

This matches the pattern used by `agentSvcHelper` in `lib.nix` and ensures that any tool available in an interactive shell is also available to agent services.

## Operational Conventions

### Email, Calendar, and Contacts

Agents have the full Pimalaya tool suite — himalaya (email), calendula (calendar), and cardamum (contacts). All auto-configured from the agent's mail credentials. See [Personal Information Management](personal-info-management.md) for usage details.

**Email (himalaya):**
- Always pipe email content via stdin, never use inline body arguments
- Use ASCII only — no unicode characters in email bodies
- Use `printf` with `\r\n` line endings (SMTP standard)
- Preview mode (`-p`) avoids marking messages as read

### Repository Cloning

All repositories are cloned to `.repos/{owner}/{repo}` within the agent-space:

```bash
git clone git@github.com:owner/repo.git .repos/owner/repo
```

### Nested Claude Sessions

When spawning a nested Claude session from within a Claude process, unset the tracking variable to avoid conflicts:

```bash
unset CLAUDECODE
claude --print -p "prompt here"
```

### Nix Dev Shell

All agent tools are managed via the `flake.nix` dev shell. Never install tools globally — use `nix develop --command <cmd>` or direnv integration.

### DeepWork Workflow Invocation

When invoking DeepWork workflows via Claude, the `/deepwork` slash command MUST be at the start of the `-p` string:

```bash
# CORRECT
claude --print -p "/deepwork task_loop run
Task: my-task
Description: do the thing"

# WRONG — model will freelance without quality gates
claude --print -p "Do the task. /deepwork task_loop run"
```
