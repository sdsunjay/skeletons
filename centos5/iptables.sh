
#!/bin/bash
# Modify script as per your setup
# Usage: Sample firewall script
# ---------------------------
_input=/some/path/iptables/blockList.txt
_pub_if="venet0"
#will differ depending on your system
IPT=/sbin/iptables

# Die if file not found
[ ! -f "$_input" ] && { echo "$0: File $_input not found."; exit 1; }

# Flushing all rules
iptables -F
iptables -X

echo DROP and close everything
# DROP and close everything
$IPT -P INPUT DROP
$IPT -P OUTPUT DROP
$IPT -P FORWARD DROP


echo Unlimited local access
# Unlimited lo access
$IPT -A INPUT -i lo -j ACCEPT
$IPT -A OUTPUT -o lo -j ACCEPT
 
#echo skipping allowing all outgoing connections
echo Allow all outgoing connection but no incoming stuff by default
# Allow all outgoing connection but no incoming stuff by default
$IPT -A OUTPUT -o ${_pub_if} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
$IPT -A INPUT -i ${_pub_if} -m state --state ESTABLISHED,RELATED -j ACCEPT

### Setup our black list ###
# Create a new chain 
$IPT -N blockList
echo starting to read: $_input
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


# Okay add your rest of $IPT commands here 
# Example: open port 53
#$IPT -A INPUT -i ${_pub_if} -s 0/0 -d 1.2.3.4 -p udp --dport 53 -j ACCEPT
#$IPT -A INPUT -i ${_pub_if} -s 0/0 -d 1.2.3.4 -p tcp --dport 53 -j ACCEPT

echo Open outgoing and incoming port 80 for web
# Open port 80 for web
$IPT -A INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT
$IPT -A INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT


echo Open incoming port 22 for ssh
# Open port 73 for ssh
$IPT -A INPUT -p tcp --dport 22 -j ACCEPT
$IPT -A OUTPUT -p tcp --sport 22 -j ACCEPT


echo Open port 25 for sendmail
#Open port 25 for sendmail
$IPT -A OUTPUT -o ${_pub_if} -p tcp --sport 25 -m state --state NEW,ESTABLISHED -j ACCEPT
$IPT -A OUTPUT -o ${_pub_if} -p tcp --dport 25 -m state --state NEW,ESTABLISHED -j ACCEPT
$IPT -A INPUT -i ${_pub_if} -p tcp --sport 25 -m state --state ESTABLISHED -j ACCEPT

echo Allow incoming ICMP ping pong stuff
 # Allow incoming ICMP ping pong stuff
$IPT -A INPUT -i ${_pub_if} -p icmp --icmp-type 8 -m state --state NEW,ESTABLISHED,RELATED -m limit --limit 30/sec  -j ACCEPT
$IPT -A INPUT -i ${_pub_if}  -p icmp -m icmp --icmp-type 3 -m limit --limit 30/sec -j ACCEPT
$IPT -A INPUT -i ${_pub_if}  -p icmp -m icmp --icmp-type 5 -m limit --limit 30/sec -j ACCEPT
$IPT -A INPUT -i ${_pub_if}  -p icmp -m icmp --icmp-type 11 -m limit --limit 30/sec -j ACCEPT
 
echo drop and log everything else
# drop and log everything else
$IPT -A INPUT -m limit --limit 5/m --limit-burst 7 -j LOG
$IPT -A INPUT -j DROP

#save IP tables rules to a file
iptables-save > /root/usefulScripts/iptables/iptables_saved

#some stuff we previously tried

# Open port 80 for web
# $IPT -A INPUT -i ${_pub_if} -p tcp --destination-port 80  -j ACCEPT
#$IPT -A INPUT -p tcp -m tcp --sport 80 -j ACCEPT
#$IPT -A OUTPUT -p tcp -m tcp --dport 80 -j ACCEPT 
#$IPT -A INPUT -p udp -m tcp --sport 80 -j ACCEPT
#$IPT -A OUTPUT -p udp -m tcp --dport 80 -j ACCEPT 

#Open port 25 for sendmail
#$IPT -A OUTPUT -p tcp --dport 25 -j ACCEPT
#$IPT -A INPUT -p tcp --sport 25 -m state --state ESTABLISHED -j ACCEPT
#$IPT -A INPUT -m state --state NEW -p tcp --dport 25 -j ACCEPT

#$IPT -A INPUT -i ${_pub_if} -p tcp --destination-port 25  -j ACCEPT
#$IPT -A OUTPUT -i ${_pub_if} -p tcp --source-port 25  -j ACCEPT

#echo Open port 22 for ssh
# Open port 22 for ssh
#SERVER_IP="172.245.22.244"
#$IPT -A OUTPUT -p tcp -s $SERVER_IP -d 0/0 –sport 513:65535 –dport 22 -m state –state NEW,ESTABLISHED -j ACCEPT
#$IPT -A INPUT -p tcp -s -d $SERVER_IP –sport 22 –dport 513:65535 -m state –state ESTABLISHED -j ACCEPT
