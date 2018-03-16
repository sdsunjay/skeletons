#!/bin/bash
# This script will help you setup your new macbook


# echo "Installing brew for you"
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
echo "brew update"
brew update
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
cowsay -f dragon hello
echo "brew install speedtest_cli"
brew install speedtest_cli
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
echo "SKIPPING brew services start mysql"
echo "brew install postgresql"
brew install postgresql
echo "SKIPPING brew install imagemagick"
# brew install imagemagick
echo "brew cask install iterm2"
brew cask install iterm2
echo "brew cask install spotify"
brew cask install spotify
echo "brew install f.lux"
brew cask install flux
echo "brew install google-chrome"
brew cask install google-chrome
echo "alias brewup='brew update; brew upgrade; brew prune; brew cleanup; brew doctor'"

echo "Type your name, followed by [ENTER]:"
read name
git config --global user.name $name 
echo "Type your email, followed by [ENTER]:"
read email
git config --global user.email $email
echo "Setting vim as your editor of choice"
git config --global core.editor vim
echo "Generating new ssh key for you using ssh-keygen!"
ssh-keygen -t rsa -b 4096 -C $email
cat ~/.ssh/id_rsa.pub