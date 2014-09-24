#find problems
date >> output.txt
echo "find problems" >> output.txt
awk '{print $9}' access.log | sort | uniq -c | sort -r >> output.txt
# summarise 301 requests
echo "Summarise 301 'Moved Permanently' requests" >> output.txt
awk '($9 ~ /301/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 400 requests
echo "Summarise 400 'Bad Request' requests" >> output.txt
awk '($9 ~ /400/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 401 requests
echo "Summarise 401 'Unauthorized' requests" >> output.txt
awk '($9 ~ /401/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 402 requests
echo "Summarise 402 'Payment Required' requests" >> output.txt
awk '($9 ~ /402/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 403 requests
echo "Summarise 403 'Forbidden' requests" >> output.txt
awk '($9 ~ /403/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 404 requests
echo "Summarise 404 'Not Found' requests" >> output.txt
awk '($9 ~ /404/)' access.log | awk '{print $4,$5,$9,$7}' | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 500 requests
echo "Summarise 500 'Internal Server Error' requests" >> output.txt
awk '($9 ~ /500/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 501 requests
echo "Summarise 501 'Not Implemented' requests" >> output.txt
awk '($9 ~ /501/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 502 requests
echo "Summarise 502 'Bad Gateway' requests" >> output.txt
awk '($9 ~ /502/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 503 requests
echo "Summarise 503 'Service Unavailable' requests" >> output.txt
awk '($9 ~ /503/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 504 requests
echo "Summarise 504 'Gateway Timeout' requests" >> output.txt
awk '($9 ~ /504/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 505 requests
echo "Summarise 505 'HTTP Version Not Supported' requests" >> output.txt
awk '($9 ~ /505/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# summarise 506 requests
echo "Summarise 506 'Variant Also Negotiates' requests" >> output.txt
awk '($9 ~ /506/)' access.log | awk '{print $4,$5,$9,$7}' | sort | uniq -c --skip-chars=25 | sort -r >> output.txt
# all user agents
echo "All User Agents" >> output.txt
awk -F\" '{print $6}' access.log | sort | uniq -c --skip-chars=25 | sort -fr >> output.txt

#blank user agents
echo "Blank User Agents" >> output.txt
awk -F\" '($6 ~ /^-?$/)' access.log >> output.txt
sed -i '/24.130.215.129/d' ./output.txt
sed -i '/Google-Apps-Script/d' ./output.txt
#whos hotlinking my images
#awk -F\" '($2 ~ /\.(jpg|gif)/ && $4 !~ /^https:\/\/www\.sunjaydhama\.com/){print $4}' access.log | sort | uniq -c | sort
