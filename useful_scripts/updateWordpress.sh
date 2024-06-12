echo Moving to /usr/share/nginx/html 
cd /usr/share/nginx/html
echo Getting latest Wordpress Version
wget --no-check-certificate https://wordpress.org/latest.tar.gz
echo unpacking 
untar latest.tar.gz 
echo deleting .tar.gz 
rm -rf latest.tar.gz 
echo deleting wp-config-sample.php
rm -rf wordpress/wp-config-sample.php 
echo copying wp-config.php to new Wordpress directory
cp blog/wp-config.php wordpress/
echo copying uploads directory to new Wordpress directory
cp -R ../../blog/wp-content/uploads wordpress/wp-content/
echo copying custom layout to new Wordpress directory
cp ~/skeletons/wordpress/wp-content/themes/twentythirteen/content.php wordpress/wp-content/themes/twentythirteen/content.php 
echo rename 'blog' to 'oldBlog'
mv blog/ oldBlog/
echo rename 'wordpress' to 'blog'
mv wordpress blog/
