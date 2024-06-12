#!/bin/bash

# Ensure the script exits on any error
set -e

# Read valid commands from file into an array
valid_commands_file="valid_commands.txt"
valid_commands_array=()

while IFS= read -r line; do
  valid_commands_array+=("$line")
done < "$valid_commands_file"

# Create a file to source functions
cat << 'EOF' > /tmp/check_valid_command.sh
#!/bin/bash
is_valid_command() {
  local cmd="$1"
  for valid_cmd in "${valid_commands_array[@]}"; do
    if [[ "$cmd" == "$valid_cmd" ]]; then
      return 0
    fi
  done
  return 1
}
EOF

# Use awk to parse the file and print invalid commands
awk -F';' -v script="/tmp/check_valid_command.sh" -v valid_commands_file="$valid_commands_file" '
BEGIN {
  while ((getline cmd < valid_commands_file) > 0) {
    valid_cmds[cmd] = 1
  }
}
{
  # Get the command part (after the semicolon)
  command = $2

  # Get the actual command name (first word of the command)
  split(command, parts, " ")
  cmd_name = parts[1]
  is_valid = (cmd_name in valid_cmds) || (cmd_name ~ /\.sh$/)
  if (!is_valid) {
    print $0
  }
}' DOT_zsh_history

