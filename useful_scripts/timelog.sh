#!/bin/bash

# File where the time logs are stored
FILE="$HOME/Documents/timelog.txt"

# Function to get the current time in human-readable format
get_current_time() {
    date "+%Y-%m-%d %H:%M:%S %z"
}

# Function to toggle the last line
toggle_last_line() {
    local line
    if ! line=$(tail -n 1 "$FILE"); then
        printf "Error: Unable to read the file\n" >&2
        return 1
    fi

    if [[ $line =~ ^start\ time ]]; then
        line=${line/start time/end time}
    elif [[ $line =~ ^end\ time ]]; then
        line=${line/end time/start time}
    else
        printf "Error: Last line format is incorrect\n" >&2
        return 1
    fi

    if ! sed -i '' -e '$d' "$FILE"; then
        printf "Error: Unable to delete the last line\n" >&2
        return 1
    fi

    if ! printf "%s\n" "$line" >> "$FILE"; then
        printf "Error: Unable to write the new line to the file\n" >&2
        return 1
    fi

    echo "Toggled: $line"
}

# Main function to log time or toggle last line
main() {
    if [[ $1 == "--toggle" || $1 == "-t" ]]; then
        if [[ ! -f $FILE ]]; then
            printf "Error: File does not exist\n" >&2
            return 1
        fi
        toggle_last_line
        return
    fi

    # Check if the file exists and determine the action based on the last log
    if [[ -f "$FILE" ]]; then
        # Read the last line from the file
        last_line=$(tail -n 1 "$FILE")
        # If the last line contains "start", log "end", otherwise log "start"
        if [[ "$last_line" =~ start\ time ]]; then
            action="end"
        else
            action="start"
        fi
    else
        # If the file doesn't exist, start with "start"
        echo "New file: $FILE"
        action="start"
    fi

    # Build the log entry
    local current_time; current_time=$(get_current_time)
    comment="$*"  # Capture all additional arguments as a comment

    # Prepare the log entry with or without comment
    local log_entry
    if [[ -n "$comment" ]]; then
        log_entry="$action time $current_time - $comment"
    else
        log_entry="$action time $current_time"
    fi

    # Log the time with the determined action and comment
    echo "$log_entry" >> "$FILE"
    echo "Logged: $log_entry"
}

main "$@"

