# Install Oh My Zsh
printf "Installing Oh My Zsh...\n"
if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
    error_exit "Failed to install Oh My Zsh"
fi
echo "Adding these plugins: plugins=(git pip zsh-syntax-highlighting nvm nmap aws brew virtualenv)"
echo "plugins=(git pip zsh-syntax-highlighting nvm nmap aws brew virtualenv)" >> ~/.zshrc
printf "Installing zsh syntax highlighting plugin"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
