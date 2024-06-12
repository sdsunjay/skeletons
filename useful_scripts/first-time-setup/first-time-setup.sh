#!/bin/sh

# Global variables
GITHUB_VUNDLE_REPO="https://github.com/gmarik/Vundle.vim.git"
VUNDLE_DIR="$HOME/.vim/bundle/Vundle.vim"
ZSHRC_FILE="$HOME/.zshrc"

# Function to handle errors
error_exit() {
    printf "Error: %s\n" "$1" >&2
    exit 1
}

# Function to echo and run commands
run_command() {
    echo "$@"
    "$@"
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

# Function to prompt for optional installation
prompt_optional_cask_pkg() {
    local pkg="$1"
    local response
    read -p "Do you want to install the optional cask package $pkg? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        install_cask_pkg "$pkg"
    else
        printf "Skipping optional cask package %s\n" "$pkg"
    fi
}

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

# Function to check and install Xcode Command Line Tools
install_xcode_command_line_tools() {
    # Check if Xcode Command Line Tools are installed
    if ! xcode-select --print-path &>/dev/null; then
        # Attempt to install Xcode Command Line Tools
        run_command xcode-select --install && return 0
        error_exit "Failed to install Xcode command line tools"
    else
        printf "Xcode Command Line Tools already installed.\n"
    fi
}

# Function to ask user to install Python
prompt_user_to_select_install_pyenv(){
    # Prompt the user for confirmation
    read -p "Do you want to select and install a Python3 version using pyenv? It is highly recommended! (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        # Execute the script to select and install Python version
	    run_command ./select-install-pyenv.sh
    else
	    echo "You selected not to select and install a version of python."
    fi

}

# Function to prompt user to install Oh My ZSH!
prompt_user_to_install_oh_my_zsh(){
    # Prompt the user for confirmation
    read -p "Do you want to install a Oh My ZSH? It is highly recommended! (y/n): " response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        # Execute the script to select and install Python version
	    run_command ./install-oh-my-zsh.sh
    else
	    echo "You selected not install Oh My ZSH!."
    fi
}

# Function to ask the user if they want to install iTerm2 shell integrations and install them if agreed
install_iterm2_shell_integration() {
    # Check if iTerm2 is installed via Homebrew
    if brew list --cask | grep -q "^iterm2$"; then
        echo "iTerm2 is installed."

        # Ask the user if they want to install iTerm2 shell integrations
        read -p "Do you want to install iTerm2 shell integrations? (y/n): " response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            # If the user agrees, run the iTerm2 shell integrations installation script
            echo "Installing iTerm2 shell integrations..."
            run_command curl -L https://iterm2.com/shell_integration/install_shell_integration_and_utilities.sh | bash
        else
            echo "Installation cancelled by user."
        fi
    else
        echo "iTerm2 is not installed. Please install iTerm2 first using 'brew install --cask iterm2'."
    fi
}

# Define the blocks of code for zsh-completions
read -r -d '' BREW_COMPINIT_BLOCK << 'EOF'
if type brew &>/dev/null; then
    FPATH=$(brew --prefix)/share/zsh/site-functions:$FPATH

    # Only run compinit if it hasn't been run already in this session
    if ! type compinit &>/dev/null; then
        autoload -Uz compinit
        compinit
    fi
fi
EOF

system_init() {

    run_command sudo systemsetup -setremotelogin off
    run_command sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
    run_command sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

    # Invert direction of mouse scroll
    run_command defaults write -g com.apple.swipescrolldirection -bool false

    # Move the dock to the left and make it smaller
    run_command defaults write com.apple.dock orientation -string left
    run_command defaults write com.apple.dock tilesize -int 30
    run_command killall Dock

    # Prompt the user for confirmation
    read -p "Do you want to disable remoted from starting using 'launchctl' (y/n): " response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        run_command sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop
        run_command sudo launchctl print system/com.apple.remoted
        run_command sudo launchctl disable system/com.apple.remoted
        run_command sudo launchctl bootout system/com.apple.remoted
    else
	    echo "You selected not disable remoted"
    fi

    # Prompt the user for confirmation
    read -p "Do you want to completely disable Siri? System restart is required. (y/n): " response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        run_command ./disable-siri.sh
    else
	    echo "You selected not disable Siri"
    fi


}

# Main function
main() {

    # Welcome message
    echo "Welcome! This script will configure various settings and install needed software for you."

    # System changes for a new OS
    system_init

    printf "This script will help you set up your new Apple computer\n"
    # Install Xcode command line tools
    install_xcode_command_line_tools

    # Install Homebrew
    printf "Installing Homebrew...\n"
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        error_exit "Failed to install Homebrew"
    fi

    # Update and upgrade brew
    run_command brew update || error_exit "Failed to update Homebrew"
    run_command brew upgrade || error_exit "Failed to upgrade Homebrew"

    # Install essential brew packages
    install_brew_pkg "bash"
    install_brew_pkg "git"
    install_brew_pkg "gpg"
    install_brew_pkg "vim"
    install_brew_pkg "wget"
    install_brew_pkg "zsh-completions"
    install_brew_pkg "ruby"
    install_brew_pkg "pyenv"
    install_brew_pkg "pyenv-virtualenv"
    run_command brew postinstall python3
    # Set permissions for zsh-completions
    printf "Setting permissions for zsh-completions... \n"
    run_command chmod go-w '/usr/local/share'
    run_command chmod -R go-w '/usr/local/share/zsh'

    # Add zsh-completions block to .zshrc
    echo "Adding zsh-completions to .zshrc"
    add_block_to_zshrc "$BREW_COMPINIT_BLOCK"
    echo "Updates to .zshrc completed."

    # Source the .zshrc to apply changes
    run_command source "$ZSHRC_FILE"
    prompt_user_to_select_install_pyenv

    # Install optional brew packages
    prompt_optional_pkg "nvm"
    prompt_optional_pkg "dockutil"
    prompt_optional_pkg "git-flow"
    prompt_optional_pkg "colordiff"
    prompt_optional_pkg "cowsay"
    prompt_optional_pkg "speedtest-cli"
    prompt_optional_pkg "python"
    prompt_optional_pkg "python-autopep8"
    prompt_optional_pkg "sqlite"
    prompt_optional_pkg "mysql"
    prompt_optional_pkg "postgresql"
    prompt_optional_pkg "tmux"
    prompt_optional_pkg "coreutils"
    prompt_optional_pkg "ansifilter"
    prompt_optional_pkg "pulseaudio"
    prompt_optional_pkg "jq"
    prompt_optional_pkg "nmap"

    # install iterm2
    install_cask_pkg "iterm2"
    # Call the function to execute the installation process
    install_iterm2_shell_integration

    # Prompt for optional cask packages
    prompt_optional_cask_pkg "brave-browser"
    prompt_optional_cask_pkg "knockknock"
    prompt_optional_cask_pkg "intellij-idea-ce"
    prompt_optional_cask_pkg "docker"
    prompt_optional_cask_pkg "little-snitch"
    prompt_optional_cask_pkg "java"
    prompt_optional_cask_pkg "spotify"
    prompt_optional_cask_pkg "google-chrome"
    prompt_optional_cask_pkg "rectangle"
    prompt_optional_cask_pkg "zoom"
    prompt_optional_cask_pkg "vlc"
    prompt_optional_cask_pkg "kindle"
    prompt_optional_cask_pkg "xquartz"

    # Clone Vundle for Vim
    printf "Cloning Vundle for Vim...\n"
    if ! git clone "$GITHUB_VUNDLE_REPO" "$VUNDLE_DIR"; then
        error_exit "Failed to clone Vundle.vim"
    fi

    # install vundle plugins
    run_command /usr/local/bin/vim +PluginInstall +qall

    # Clean up outdated brew packages
    printf "Cleaning up outdated brew packages...\n"
    if ! brew cleanup; then
        error_exit "Failed to clean up"
    fi


    # Configure Git
    # Ask the user if they want to install iTerm2 shell integrations
    read -p "Do you want to configure git? (y/n): " response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        # If the user agrees, run the git config commands
        printf "Configuring Git...\n"
        local name email comment
        name=$(prompt_user_input 'Type your name, followed by [ENTER]: ')
        email=$(prompt_user_input 'Type your email, followed by [ENTER]: ')
        git config --global user.name "$name"
        git config --global user.email "$email"
        git config --global core.editor vim
    fi

    response=$(prompt_user_input 'Do you want to generate an ssh key? (y/n): ')

    if [[ "$response" =~ ^[Yy]$ ]]; then
      # Generate SSH key
      comment=$(prompt_user_input 'Type your comment for SSH key, followed by [ENTER]: ')
      printf "Generating new SSH key...\n"
      printf "ssh-keygen -t rsa -b 4096 -C $comment"
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
    fi

    prompt_user_to_install_oh_my_zsh

    # Demonstrate `cowsay` if installed
    if brew list cowsay &>/dev/null; then
        echo "Congratulations on finishing the setup!" | cowsay -f dragon
    fi

    # Reload the shell to apply `.zshrc` changes
    run_command source $ZSHRC_FILE

    # Prompt the user for confirmation
    read -p "Do you want to install node, npm, typescript, aws-cli. It is highly recommended! (y/n): " response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "now running node-aws-cdk-setup.sh"
        run_command ./node-aws-cdk-setup.sh
    else
	    echo "You selected not install node, npm, typescript, nor aws-cli."
    fi
}

# Execute main function
main

