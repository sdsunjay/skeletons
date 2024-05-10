#!/bin/bash

# Global variables
GITHUB_VUNDLE_REPO="https://github.com/gmarik/Vundle.vim.git"
VUNDLE_DIR="$HOME/.vim/bundle/Vundle.vim"
ZSHRC_FILE="$HOME/.zshrc"

# Function to handle errors
error_exit() {
    printf "Error: %s\n" "$1" >&2
    exit 1
}

# Function to prompt user input with validation
prompt_user_input() {
    local prompt_msg="$1"
    local user_input
    read -p "$prompt_msg" user_input
    if [[ -z "$user_input" ]]; then
        error_exit "Input cannot be empty"
    fi
    printf "%s" "$user_input"
}

# Function to install a brew package
install_brew_pkg() {
    local pkg="$1"
    printf "Installing %s...\n" "$pkg"
    if ! brew install "$pkg"; then
        error_exit "Failed to install $pkg"
    fi
}

# Function to install a cask package
install_cask_pkg() {
    local pkg="$1"
    printf "Installing cask package %s...\n" "$pkg"
    if ! brew install --cask "$pkg"; then
        error_exit "Failed to install cask package $pkg"
    fi
}

# Function to tap a brew repository
tap_brew_repo() {
    local repo="$1"
    printf "Tapping %s...\n" "$repo"
    if ! brew tap "$repo"; then
        error_exit "Failed to tap $repo"
    fi
}

# Function to prompt for optional installation
prompt_optional_pkg() {
    local pkg="$1"
    local response
    read -p "Do you want to install the optional package $pkg? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        install_brew_pkg "$pkg"
    else
        printf "Skipping optional package %s\n" "$pkg"
    fi
}

# Function to add blocks of commands to .zshrc
add_block_to_zshrc() {
    local block="$1"
    local pattern=$(echo "$block" | head -n 1) # Use the first line of the block as a pattern

    # Check if .zshrc exists, create if it does not
    if [[ ! -f "$ZSHRC_FILE" ]]; then
        touch "$ZSHRC_FILE"
    fi

    # Append block if the pattern is not already in the file
    if ! grep -qF "$pattern" "$ZSHRC_FILE"; then
        printf "\n%s\n" "$block" >> "$ZSHRC_FILE"
    fi
}



# Function to check and install Xcode Command Line Tools
install_xcode_command_line_tools() {
    # Check if Xcode Command Line Tools are installed
    if ! xcode-select --print-path &>/dev/null; then
        # Attempt to install Xcode Command Line Tools
        xcode-select --install && return 0
        error_exit "Failed to install Xcode command line tools"
    else
        printf "Xcode Command Line Tools already installed.\n"
    fi
}

# Define the blocks of code
# for zsh-completions
BREW_COMPINIT_BLOCK="if type brew &>/dev/null; then
    FPATH=\$(brew --prefix)/share/zsh-completions:\$FPATH
    autoload -Uz compinit
    compinit
fi"

# for pyenv
PYENV_BLOCK="eval \"\$(pyenv init -)\"
if which pyenv-virtualenv-init > /dev/null; then
    eval \"\$(pyenv virtualenv-init -)\"
fi"

# Main function
main() {
    printf "This script will help you set up your new Apple computer\n"

    # Install Xcode command line tools
    install_xcode_command_line_tools
    
    # Install Homebrew
    printf "Installing Homebrew...\n"
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        error_exit "Failed to install Homebrew"
    fi

    # Update and upgrade brew
    brew update || error_exit "Failed to update Homebrew"
    brew upgrade || error_exit "Failed to upgrade Homebrew"

    # Install essential brew packages
    install_brew_pkg "git"
    install_brew_pkg "gpg"
    install_brew_pkg "vim"
    install_brew_pkg "wget"
    install_brew_pkg "zsh-completions"
    install_brew_pkg "ruby"
    install_brew_pkg "pyenv"
    install_brew_pkg "pyenv-virtualenv"

    # Set permissions for zsh-completions
    printf "Setting permissions for zsh-completions... \n"
    chmod go-w '/usr/local/share'
    chmod -R go-w '/usr/local/share/zsh'


    # Add blocks to .zshrc
    echo "Adding zsh-completions to .zshrc"
    add_block_to_zshrc "$BREW_COMPINIT_BLOCK"
    echo "Adding pyenv to .zshrc"
    add_block_to_zshrc "$PYENV_BLOCK"

    echo "Updates to .zshrc completed."

    # Install optional brew packages
    prompt_optional_pkg "dockutil"
    prompt_optional_pkg "git-flow"
    prompt_optional_pkg "colordiff"
    prompt_optional_pkg "cowsay"
    prompt_optional_pkg "speedtest-cli"
    prompt_optional_pkg "python"
    prompt_optional_pkg "sqlite"
    prompt_optional_pkg "mysql"
    prompt_optional_pkg "postgresql"
    prompt_optional_pkg "tmux"
    prompt_optional_pkg "coreutils"
    prompt_optional_pkg "ansifilter"
    prompt_optional_pkg "spectacle"
        
    install_cask_pkg "iterm2"

    # Prompt for optional cask packages
    local response
    read -p "Do you want to install optional cask packages (java, spotify, google-chrome, vlc, kindle)? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        install_cask_pkg "java"
        install_cask_pkg "spotify"
        install_cask_pkg "google-chrome"
        install_cask_pkg "vlc"
        install_cask_pkg "kindle"
    else
        printf "Skipping optional cask packages\n"
    fi

    # Clone Vundle for Vim
    printf "Cloning Vundle for Vim...\n"
    if ! git clone "$GITHUB_VUNDLE_REPO" "$VUNDLE_DIR"; then
        error_exit "Failed to clone Vundle.vim"
    fi

    # Clean up outdated brew packages
    printf "Cleaning up outdated brew packages...\n"
    if ! brew cleanup; then
        error_exit "Failed to clean up"
    fi

    # Configure Git
    printf "Configuring Git...\n"
    local name email comment
    name=$(prompt_user_input 'Type your name, followed by [ENTER]: ')
    email=$(prompt_user_input 'Type your email, followed by [ENTER]: ')
    git config --global user.name "$name"
    git config --global user.email "$email"
    git config --global core.editor vim

    # Generate SSH key
    comment=$(prompt_user_input 'Type your comment for SSH key, followed by [ENTER]: ')
    printf "Generating new SSH key...\n"
    if ! ssh-keygen -t rsa -b 4096 -C "$comment"; then
        error_exit "Failed to generate SSH key"
    fi

    # Display generated SSH public key
    if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        printf "Your new SSH public key:\n"
        cat "$HOME/.ssh/id_rsa.pub"
    else
        error_exit "Public SSH key not found"
    fi

    # Demonstrate `cowsay` if installed
    if brew list cowsay &>/dev/null; then
        echo "Congratulations on finishing the setup!" | cowsay -f dragon
    fi

    # Reload the shell to apply `.zshrc` changes
    exec zsh
}

# Execute main function
main

