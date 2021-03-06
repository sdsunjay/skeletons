#!/bin/bash
# This script will help you setup your new macbook
echo "This script will help you setup your new Apple computer"
echo "Installing brew for you"
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
echo "brew tap caskroom/cask"
brew tap caskroom/cask
echo "brew install dockutil (don't forget to run this later)"
brew install dockutil
echo "brew install gpg"
brew install gpg
echo "brew install git"
brew install git
echo "brew install git-flow"
brew install git-flow
echo "brew install colordiff"
brew install colordiff
echo "brew install cowsay"
brew install cowsay
echo "cowsay -f dragon hello"
cowsay -f dragon hello
echo "brew install speedtest_cli"
brew install speedtest_cli
echo "brew tap caskroom/versions"
brew tap caskroom/versions
echo "brew cask install java"
brew cask install java
echo "brew install python3"
brew install python3
echo "pip3 install virtualenv"
pip3 install virtualenv
echo "brew install wget"
brew install wget
echo "brew install bash-completion"
brew install bash-completion
echo "brew install sqlite3"
brew install sqlite3
echo "brew install mysql"
brew install mysql
echo "brew tap homebrew/services"
brew tap homebrew/services
echo "brew install coreutils"
brew install coreutils
echo "SKIPPING brew services start mysql"
echo "brew install postgresql"
brew install postgresql
echo "brew install vim"
brew install vim
echo "brew install tmux"
brew install tmux
echo "brew install ansifilter"
brew install ansifilter
echo "git clone Vundle"
git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
echo "SKIPPING brew install imagemagick"
# brew install imagemagick
echo "brew cask install iterm2"
brew cask install iterm2
echo "brew cask install spotify"
brew cask install spotify
# echo "SKIPPING brew install f.lux"
# brew cask install flux
echo "brew install google-chrome"
brew cask install google-chrome
# echo "brew cask install atom"
# brew cask install atom
echo "brew cask install vlc"
brew cask install vlc
echo "brew cask install kindle"
brew cask install kindle
echo "SKIPPING brew cask install gimp"
# brew cask install gimp
echo "SKIPPING brew cask install vagrant"
# brew cask install vagrant

echo "brew cleanup"
brew cleanup

read -p 'Type your name, followed by [ENTER]: ' name
git config --global user.name $name
read -p 'Type your email, followed by [ENTER]: ' email
git config --global user.email $email
echo "Setting vim as your editor of choice"
git config --global core.editor vim
echo "Generating new SSH key for you using ssh-keygen!"
read -p 'Type your comment for SSH key, followed by [ENTER]: ' comment
echo "ssh-keygen -t rsa -b 4096 -C $comment"
ssh-keygen -t rsa -b 4096 -C "$comment"
echo "cat ~/.ssh/id_rsa.pub"
cat ~/.ssh/id_rsa.pub
