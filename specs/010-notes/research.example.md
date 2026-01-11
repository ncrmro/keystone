# Research: Example Project for Keystone Notes

This document provides a concrete example of what the user's notes repository will look like and how the system will interact with it.

## Directory Structure

```text
~/notes/
├── .keystone/
│   └── jobs.toml         # Configuration for the agent
├── daily/
│   ├── 2025-01-01.md
│   └── 2025-01-02.md
├── projects/
│   └── keystone/
│       └── ideas.md
├── scripts/
│   ├── summarize.sh      # User-defined script to gather context
│   └── fetch-movies.py   # User-defined script to fetch external data
└── README.md
```

## Configuration (`.keystone/jobs.toml`)

```toml
[global]
backend = "claude-code"
use_mcp = true

# Job 1: Daily Summary
# Runs every morning at 8 AM.
# It runs a script to "cat" yesterday's note, sends it to Claude,
# and appends the result to today's note.
[[jobs]]
name = "daily-summary"
schedule = "0 8 * * *"
script = "scripts/summarize.sh"
context_mode = "diff" # Send recent changes to the agent
context_lookback = "24h"

# Job 2: Sync
# Runs every 15 minutes to keep notes synced across devices.
[[jobs]]
name = "sync"
schedule = "*/15 * * * *"
script = "builtin:sync"

# Job 3: Movie Recommendations
# Runs every Friday at 6 PM.
# Fetches data from an API and asks the agent to pick a movie.
[[jobs]]
name = "movie-night"
schedule = "0 18 * * FRI"
script = "scripts/fetch-movies.py"
backend = "ollama" # Use local model for fun/privacy
```

## User Scripts

### `scripts/summarize.sh`

```bash
#!/bin/bash
# Gather context for the agent
echo "Task: Summarize the following notes from yesterday and list open tasks for today."
echo "---"
cat daily/$(date -d "yesterday" +%F).md
```

### `scripts/fetch-movies.py`

```python
#!/usr/bin/env python3
import requests
import json

# Fetch data
response = requests.get("https://api.example.com/movies/now-playing")
movies = response.json()

# Format for the agent
print("Here are the movies playing now:")
for movie in movies:
    print(f"- {movie['title']} (Rating: {movie['rating']})")

print("\nTask: Pick one movie from this list that is a Sci-Fi thriller and explain why I should watch it.")
```

## Workflow

1.  **Setup**: User creates the `~/notes` repo and adds the files above.
2.  **Trust**: User runs `keystone-notes allow .` to hash and approve the scripts.
3.  **Install**: User runs `keystone-notes install-jobs` to generate systemd timers.
4.  **Execution (Automated)**:
    - **8:00 AM**: `daily-summary` timer fires.
    - Systemd runs `keystone-notes run daily-summary`.
    - `keystone-notes` executes `scripts/summarize.sh` (output captured).
    - `keystone-notes` calls Claude Code via MCP with the script output + git diffs.
    - Agent generates summary text.
    - `keystone-notes` appends the summary to `daily/2025-01-02.md` (or creates a new file).
5.  **Execution (Manual)**:
    - User types `keystone-notes run movie-night`.
    - Python script runs, fetches data.
    - Ollama model picks a movie.
    - Result is appended to `daily/2025-01-02.md`.
