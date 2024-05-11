#!/bin/bash

# File where the time logs are stored
FILE="$HOME/Documents/timelog.txt"

# Function to get the current time in human-readable format
get_current_time() {
    date "+%Y-%m-%d %H:%M:%S %z"
}

# Check if the file exists and determine the action based on the last log
if [ -f "$FILE" ]; then
    # Read the last line from the file
    last_line=$(tail -n 1 "$FILE")
    # If the last line contains "start", log "end", otherwise log "start"
    if [[ "$last_line" =~ start ]]; then
        action="end"
    else
        action="start"
    fi
else
    # If the file doesn't exist, start with "start"
    action="start"
fi

# Build the log entry
current_time=$(get_current_time)
comment="$*"  # Capture all additional arguments as a comment

# Prepare the log entry with or without comment
if [[ -n "$comment" ]]; then
    log_entry="$action time $current_time - $comment"
else
    log_entry="$action time $current_time"
fi

# Log the time with the determined action and comment
echo "$log_entry" >> $FILE
echo "Logged: $log_entry"

