# Backup mysql db and upload to dropbox using andreafabrizi/Dropbox-Uploader@871ad082d81bf23e336da9746627bc083c35eb8a
sudo mysqldump -u root -p NAME_OF_DATABASE | gzip -c > ./blog_backup.sql.gz;
if [ ${PIPESTATUS[0]} -ne "0" ];
then
  echo "\nthe command \"mysqldump\" failed with Error: ${PIPESTATUS[0]}";
  exit 1;
else
  tar -cjf blog.tar.bz2 blog_backup.sql.gz
  name=$(date +%Y-%m-%d_%H:%M)
  mv blog.tar.bz2 "/root/$name.blog.tar.bz2"
  echo uploading $name.blog.tar.bz2 to Dropbox Account
  ~/Dropbox-Uploader/dropbox_uploader.sh -s -p upload "/root/$name.blog.tar.bz2" blog
  # Backup the uploads folder in my wordpress blog
  uploads="/usr/share/nginx/html/blog/wp-content/uploads"
  echo uploading $uploads
  ~/Dropbox-Uploader/dropbox_uploader.sh -s -p upload $uploads blog
fi
rm -rf blog_backup.sql.gz
-rf $name.blog.tar.bz2
