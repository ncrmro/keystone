#!/bin/bash
# Gather context for the agent
echo "Task: Summarize the following notes from yesterday and list open tasks for today."
echo "---"
# Check if yesterday's file exists before catting
YESTERDAY=$(date -d "yesterday" +%F)
FILE="daily/${YESTERDAY}.md"

if [ -f "$FILE" ]; then
    cat "$FILE"
else
    echo "No notes found for yesterday ($YESTERDAY)."
fi
