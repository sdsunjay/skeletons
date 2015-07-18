if [ -z "$1" ]   
then
   echo enter package that you wish to install
   read x
else
   x=$1
fi

echo stopping nginx
sudo service nginx stop
echo stopping php
sudo service php-fpm stop
echo stopping  mysql
sudo service mysqld stop

sudo yum install $x

echo starting mysql
sudo service mysqld start
echo starting php
sudo service php-fpm start

echo starting nginx
sudo service nginx start
