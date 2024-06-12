#!/bin/sh

# Check if the script is running in zsh, if not re-run it with zsh
if [ -z "$ZSH_VERSION" ]; then
  exec zsh "$0" "$@"
fi

ZSHRC_FILE="$HOME/.zshrc"

# Block of commands to add to .zshrc for pyenv
read -r -d '' PYENV_BLOCK << 'EOF'
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
if which pyenv-virtualenv-init > /dev/null; then
    eval "$(pyenv virtualenv-init -)"
fi
EOF

# Function to add blocks of commands to .zshrc
add_block_to_zshrc() {
    local block="$1"
    local first_line=$(echo "$block" | head -n 1) # Use the first line of the block as a pattern

    # Check if .zshrc exists, create if it does not
    if [[ ! -f "$ZSHRC_FILE" ]]; then
        touch "$ZSHRC_FILE"
    fi

    # Append block if the pattern is not already in the file
    if ! grep -qF "$first_line" "$ZSHRC_FILE"; then
        printf "\n%s\n" "$block" >> "$ZSHRC_FILE"
        echo "Block added to $ZSHRC_FILE"
    else
        echo "Block already exists in $ZSHRC_FILE"
    fi
}

echo "Adding pyenv config block to $ZSHRC_FILE"
add_block_to_zshrc "$PYENV_BLOCK"
echo "Updates to .zshrc completed."

# Source the .zshrc to apply changes
source "$ZSHRC_FILE"
