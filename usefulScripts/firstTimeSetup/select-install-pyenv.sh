#!/bin/bash

# Check if pyenv is installed and accessible
if ! command -v pyenv >/dev/null 2>&1; then
    printf "pyenv is not installed or not found in PATH. Please install pyenv first.\n" >&2
    return 1
fi

# Function to list the last 20 Python 3.x versions available for installation with pyenv
list_python_versions() {
    local versions

    if ! versions=$(pyenv install --list | grep --extended-regexp '^\s*3\.[0-9]+\.[0-9]+\s*$' | tail -10 | tr -d ' '); then
        printf "Failed to fetch Python versions.\n" >&2
        return 1
    fi

    echo "$versions"
}

# Function to prompt the user to select a Python version and install it using pyenv
install_selected_version() {
    local versions=$1
    local selection

    printf "Available Python 3.x versions:\n%s\n" "$versions"
    printf "Enter the version you want to install: "
    read -r selection

    if [[ -z "$selection" ]]; then
        printf "No version selected. Exiting.\n" >&2
        return 1
    fi

    if ! echo "$versions" | grep -q "^$selection$"; then
        printf "Invalid version selected. Exiting.\n" >&2
        return 1
    fi

    printf "Installing Python %s...\n" "$selection"
    if ! pyenv install "$selection"; then
        printf "Failed to install Python %s.\n" "$selection" >&2
        return 1
    fi

    printf "Python %s installed successfully.\n" "$selection"
}

main() {
    local available_versions

    if ! available_versions=$(list_python_versions); then
        printf "Error: Could not retrieve available Python versions.\n" >&2
        return 1
    fi

    if ! install_selected_version "$available_versions"; then
        return 1
    fi
}

main

