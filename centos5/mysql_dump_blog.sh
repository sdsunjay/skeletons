echo password is password
sudo mysqldump -u root -p blog | gzip -c > ./blog_backup.sql.gz;
if [ ${PIPESTATUS[0]} -ne "0" ];
then
   echo "\nthe command \"mysqldump\" failed with Error: ${PIPESTATUS[0]}";
   exit 1;
else
   tar -cjf blog.tar.bz2 blog_backup.sql.gz
   name=$(date +%Y-%m-%d_%H:%M)
   mv blog.tar.bz2 "/root/$name.blog.tar.bz2"
   /root/dropbox/Dropbox-Uploader/dropbox_uploader.sh upload "/root/$name.blog.tar.bz2" blog
fi
   rm -rf blog_backup.sql.gz
   rm -rf $name.blog.tar.bz2
