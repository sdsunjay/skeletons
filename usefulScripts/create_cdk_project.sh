#!/bin/sh

# Function to echo and run commands
run_command() {
    echo "$@"
    "$@"
}

# Function to select programming language for the new project
function select_programming_language_for_project() {
    local language
    local languages=("typescript" "javascript" "python" "java" "csharp" "go")
    while true; do
        printf "Select a programming language: \n"
        select language in "${languages[@]}"; do
            if [[ -n "$language" ]]; then
                printf "Selected language: %s\n" "$language"
                printf "Selected number: %s\n" "$REPLY"
                # Initialize a new CDK app with the specified language
                run_command cdk init app --language "$LANGUAGE"
                return 0
            else
                printf "Invalid selection: %s\n\n" "$REPLY"
                break
            fi
        done
    done
}

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <project-name>"
    exit 1
fi

# Assign the project name based on user input
PROJECT_NAME=$1

# Create and navigate to the new project directory
run_command mkdir "$PROJECT_NAME"
run_command cd "$PROJECT_NAME"

select_programming_language_for_project

# List directory contents
run_command ls

# Build the project using npm
run_command npm run build

# Open the main stack file in vim for editing
run_command vim lib/"${PROJECT_NAME}-stack.ts"

