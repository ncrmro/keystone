---
title: First Days on Keystone
description: One canonical path from a fresh shell to productive daily use — SSH, repos, Zellij, Lazygit, notes, and project context
---

# First Days on Keystone

This guide takes a new Keystone user from a fresh interactive shell to productive
daily use in one pass. Follow the steps in order. Each section includes a
verification command so you know the step succeeded before moving on.

If you are returning after a gap, jump to [Resume your workspace](#resume-your-workspace).

---

## 1. Verify SSH agent

Keystone runs `ssh-agent` as a systemd user service and exports `SSH_AUTH_SOCK`
into every session automatically.

```bash
# Check the socket exists
echo $SSH_AUTH_SOCK
# Expected: /run/user/1000/ssh-agent

# Check the agent is reachable
ssh-add -l
# Expected: "The agent has no identities." or a list of loaded keys
# NOT: "Could not open a connection to your authentication agent"

# Check the service is running
systemctl --user status ssh-agent
# Expected: active (running)
```

If the agent is not running:

```bash
systemctl --user start ssh-agent
```

For full troubleshooting, see [SSH Agent](../os/ssh-agent.md).

### First SSH use

The first time you `git clone` or `ssh` using a passphrase-protected key, you
will be prompted for the passphrase once. Keystone's SSH config includes
`AddKeysToAgent yes`, so the key is cached for the rest of the session. You will
not be prompted again until you restart the agent.

---

## 2. Check out a repo

Keystone separates two classes of repo:

| Class | Root | Example |
|---|---|---|
| Keystone-managed (flake inputs) | `~/.keystone/repos/{owner}/{repo}` | `~/.keystone/repos/ncrmro/keystone` |
| Non-Keystone project repos | `$HOME/code/{owner}/{repo}` | `$HOME/code/ncrmro/my-app` |

Use `~/.keystone/repos/` only for repos managed by `ks` as flake inputs. For
everything else, use `$HOME/code/`.

```bash
# Clone a non-Keystone project repo
mkdir -p "$HOME/code/ncrmro"
git clone git@github.com:ncrmro/my-app.git "$HOME/code/ncrmro/my-app"
cd "$HOME/code/ncrmro/my-app"
```

Verify:

```bash
pwd
# Expected: /home/<user>/code/ncrmro/my-app

git remote -v
# Expected: origin  git@github.com:ncrmro/my-app.git (fetch)
```

---

## 3. Bootstrap your notes repo

Project-aware commands (`pz`, agent workflows) read the notes repo at `~/notes`.
If you have not set it up yet, do that now before continuing.

```bash
# Check if a notes repo exists
ls ~/notes
```

If the directory is empty or missing, initialize it with the notes workflow:

```
ks.notes
```

Follow the prompts to clone or create your notes notebook.

Verify:

```bash
systemctl --user status keystone-notes-sync
# Expected: active (running) or at least loaded

ls ~/notes/index/
# Expected: one or more .md hub notes
```

---

## 4. Open a project session with pz

`pz` is the Keystone project session launcher. It reads active hub notes from
`~/notes/index/` and creates or attaches to a named Zellij session.

```bash
# List discoverable projects
pz list

# Open a session for a specific project
pz my-project
```

If your project does not appear in `pz list`, the hub note may be missing or
stale. Check the notes sync status, then inspect the index:

```bash
systemctl --user status keystone-notes-sync
zk edit -i   # browse and find or create the hub note
```

A valid hub note includes:

```yaml
---
project: "my-project"
repos:
  - "git@github.com:ncrmro/my-app.git"
tags: [index, project/my-project, status/active]
---
```

After adding or fixing the hub note, `pz list` should show the project.

---

## 5. Work inside your Zellij session

Once inside a `pz` session, use Zellij to organize your workspace with tabs and panes.

### Core Zellij operations

```bash
# Create or attach to a named session (if not using pz)
zellij -s my-project

# List all sessions
zellij list-sessions

# Attach to an existing session
zellij attach my-project

# Detach (leave the session running)
# Press: Ctrl+o then d

# Switch tabs
# Press: Ctrl+PageUp / Ctrl+PageDown

# Name a new tab (from the shell)
znewtab

# Rename the current tab explicitly
ztab "my-tab-name"
```

> **Note:** The Keystone terminal module ships `ztab` and `znewtab` as the
> supported tab helpers. Use these instead of raw `zellij` tab commands.

### Create a new pane

```
# Press: Ctrl+p then n
```

### Floating pane (quick scratch terminal)

```
# Press: Ctrl+p then w
```

---

## 6. Use Lazygit

From inside any git repo in your session:

```bash
lazygit
# Or using the shell alias:
lg
```

Both `lazygit` and `lg` are available. Use `lg` as your default inside a `pz`
session for speed.

---

## 7. End-to-end example

This example starts from a fresh shell, checks out a repo, opens a project session,
creates a tab, uses Lazygit, then detaches and resumes.

```bash
# 1. Verify SSH is ready
echo $SSH_AUTH_SOCK && ssh-add -l

# 2. Clone the repo
mkdir -p "$HOME/code/ncrmro"
git clone git@github.com:ncrmro/my-app.git "$HOME/code/ncrmro/my-app"

# 3. Ensure notes are current
systemctl --user status keystone-notes-sync

# 4. Open a project session
pz my-project
# (or: zellij -s my-project)

# 5. Create a tab named "code"
ztab "code"

# 6. Open Lazygit
cd "$HOME/code/ncrmro/my-app"
lg

# 7. Detach (keep session alive)
# Press: Ctrl+o then d

# 8. Resume the same session later
pz my-project
# (or: zellij attach my-project)
```

---

## Resume your workspace

If you are returning to existing work:

```bash
# See what sessions are running
zellij list-sessions

# Reattach
pz my-project
# or
zellij attach my-project
```

If a session no longer exists (machine rebooted, etc.), re-run `pz my-project`
and it creates a fresh session with the project environment variables set.

---

## Environment variables

When `pz` creates a session, it sets:

| Variable | Value |
|---|---|
| `NOTES_DIR` | `~/notes` |
| `CODE_DIR` | `$HOME/code` |
| `WORKTREE_DIR` | `$HOME/.worktrees` |
| `PROJECT_NAME` | the project slug |
| `PROJECT_PATH` | resolved project checkout path |

These are available to shells, scripts, and agent workflows running inside the
session.

---

## Related docs

- [SSH Agent](../os/ssh-agent.md) — SSH key management and troubleshooting
- [TUI Developer Workflow](tui-developer-workflow.md) — full tool reference (Helix, Zellij, yazi, fzf)
- [Projects and pz](projects.md) — hub notes, repo roots, session naming
- [Notes](../notes.md) — notebook structure and zk workflow
