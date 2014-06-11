
_input=/root/blockList.txt
_pub_if="venet0"
IPT=/sbin/iptables

# Unlimited lo access
$IPT -A INPUT -i lo -j ACCEPT
$IPT -A OUTPUT -o lo -j ACCEPT
 
# Allow all outgoing connection but no incoming stuff by default
$IPT -A OUTPUT -o ${_pub_if} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
$IPT -A INPUT -i ${_pub_if} -m state --state ESTABLISHED,RELATED -j ACCEPT

# Filter out comments and blank lines
# store each ip or subnet in $ip
while IFS= read -r ip
do
        # Append everything to droplist
   $IPT -A blockList -i ${_pub_if} -s $ip -j LOG --log-prefix " Drop Bad IP List "
   $IPT -A blockList -i ${_pub_if} -s $ip -j DROP
done <"${_input}"
 
# Finally, insert or append our black list 
$IPT -I INPUT -j blockList
$IPT -I OUTPUT -j blockList
$IPT -I FORWARD -j blockList
