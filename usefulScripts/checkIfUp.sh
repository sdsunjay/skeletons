#! /bin/sh
function check {
     if [ $? -ne 0 ] ; then
         echo "Error occurred getting URL $1:"
         #to text myself
	#curl http://textbelt.com/text -d number=########## -d "message=sunjaydhama.com is down!" 
	mutt -s "sunjaydhama.com is down" youremail@domain.com < /root/message.txt
	#echo "$(date)" | mail -s "sunjaydhama.com is down!" dhamaharpal@gmail.com


	if [ $? -eq 6 ]; then
            echo "Unable to resolve host"
        fi
        if [ $? -eq 7 ]; then
            echo "Unable to connect to host"
        fi
         exit 1
     fi

}
url="https://www.sunjaydhama.com/gui/new/index.html"
destdir=/root/message.txt
response=$(curl --write-out %{http_code} --silent --output /dev/null servername)

#write date into new file
DATE=`date +\%Y\%m\%d`

#append reponse to file
if [ -f "$destdir" ]
then 
    $DATE > $destdir 2>&1
    echo "$response" >> "$destdir"
fi
curl -s -o "/dev/null" $url
check $url;

#if curl -s --head  --request GET https://www.sunjaydhama.com/gui/new/index.html | grep "200 OK" > /dev/null && curl -s --head --request GET https://www.sunjaydhama.com/gui/new/index.html | grep "200 OK" > /dev/null;
