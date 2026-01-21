---
layout: default
title: Notes Agent
---

# Keystone Notes Agent (`keystone-notes`)

The Keystone Notes Agent is a personal AI assistant that lives inside your notes repository. It automates maintenance tasks, synchronizes your notes across devices, and uses AI to summarize your daily activities.

Unlike cloud-based note-taking apps, the Notes Agent runs **locally** on your machine, respects your privacy, and works with standard Markdown files.

## How It Works

The agent runs as a background service on your computer (using Systemd). It follows a simple loop:

1.  **Sync**: It regularly synchronizes your notes with a Git repository (like GitHub or a private server).
2.  **Read**: It looks at what you've written in your daily notes.
3.  **Think**: It uses an AI model (like Claude, Gemini, or a local Ollama model) to analyze your content.
4.  **Act**: It writes summaries, extracts tasks, or creates new notes based on your instructions.

## Key Features

-   **Automated Sync**: Never worry about `git commit` and `git push` again. The agent handles merge conflicts automatically.
-   **Daily Summaries**: The agent reads your daily note and generates a concise summary of what you accomplished.
-   **Local & Private**: Works with local text files. You control which AI backend is used (including fully offline local models).
-   **Extensible**: You can write your own scripts (Python, Bash, etc.) and schedule them as agent jobs.

## Getting Started

### 1. Installation

The agent is available as a Nix package.

```bash
nix profile install .#keystone-notes
```

### 2. Configuration (`.keystone/jobs.toml`)

Create a configuration file in the root of your notes folder:

```toml
[global]
backend = "claude-code" # Options: "claude-code", "gemini", "ollama"

# 1. Background Sync Job
[[jobs]]
name = "sync"
schedule = "*:0/10" # Run every 10 minutes
script = "builtin:sync"

# 2. AI Summary Job
[[jobs]]
name = "daily-summary"
schedule = "08:00" # Run every morning at 8 AM
script = """
Please summarize the key technical decisions made in yesterday's daily note.
Append the summary to a new section in today's note.
"""
context_mode = "diff"
context_lookback = "24h"
```

### 3. Activate

Register the jobs with your system:

```bash
cd ~/my-notes
keystone-notes install-jobs
```

## Daily Workflow

### Opening Your Notes
Instead of navigating folders, just type:

```bash
keystone-notes daily
```

This opens today's note (e.g., `daily/2026-01-11.md`) in your preferred editor (`$EDITOR`).

### Checking Status
Open the interactive dashboard to see what the agent is doing:

```bash
keystone-notes tui
```

You can see:
-   Last sync time
-   Success/Failure of AI jobs
-   Logs of what the agent "thought"

## Security: The Trust Model

To prevent malicious code execution, the agent uses a **Trust Store**.

If you define a job that runs a script (e.g., `scripts/cleanup.sh`), the agent will **refuse to run it** until you explicitly approve it.

```bash
# Approve a specific script
keystone-notes allow scripts/cleanup.sh

# Approve all scripts in the current directory (recursive)
keystone-notes allow .
```

If you modify the script, the agent will detect the change and pause execution until you approve the new version.

## Architecture

The agent is built in **Rust** for performance and reliability.

-   **Binary**: Single executable `keystone-notes`.
-   **Scheduler**: Uses `systemd --user` timers (standard Linux scheduling).
-   **State**: Stores trust database and logs in `~/.local/share/keystone/`.
