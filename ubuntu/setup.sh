apt-get update
apt-get upgrade
useradd deploy
mkdir /home/deploy
mkdir /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 400 /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy -R
passwd deploy
vim /etc/ssh/sshd_config
service ssh restart
