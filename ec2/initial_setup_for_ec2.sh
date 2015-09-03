apt-get install git unzip
read -p "What is your first and last name (for git configuration)? " fn ln
git config --global user.name "$fn $ln"
read -p "What is your email (for git configuration)? " email
git config --global user.email $email
echo "Your default editor is vim (the best text editor ever!)"
git config --global core.editor vim
git config --list
echo "Generating SSH key"
ssh-keygen -t rsa
cat ~/.ssh/id_rsa.pub
