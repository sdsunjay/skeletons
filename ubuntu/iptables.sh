#!/bin/bash
# Modify script as per your setup
# Usage: Sample firewall script
# ---------------------------
# some stuff came from here,
# http://www.thegeekstuff.com/scripts/iptables-rules
# http://www.rackspace.com/knowledge_center/article/mail-server-opening-ports-in-the-linux-firewall
# Path to block list
_input=/home/deploy/blockList.txt
# interface
_pub_if="eth0"
# Will differ depending on your system
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
# $IPT -N droplist
 
# Filter out comments and blank lines
# store each ip or subnet in $ip
# while IFS= read -r ip
#do
        # Append everything to droplist
#	$IPT -A droplist -i ${_pub_if} -s $ip -j LOG --log-prefix " Drop Bad IP List "
#	$IPT -A droplist -i ${_pub_if} -s $ip -j DROP
# done <"${_input}"
 
# Finally, insert or append our black list 
# $IPT -I INPUT -j droplist
# $IPT -I OUTPUT -j droplist
# $IPT -I FORWARD -j droplist

# Okay add your rest of $IPT commands here 
# Example: open port 53
#$IPT -A INPUT -i ${_pub_if} -s 0/0 -d 1.2.3.4 -p udp --dport 53 -j ACCEPT
#$IPT -A INPUT -i ${_pub_if} -s 0/0 -d 1.2.3.4 -p tcp --dport 53 -j ACCEPT

echo Open outgoing and incoming port 80 and 443 for web
# Open port 80 for web
#http
$IPT -A INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT
#https
$IPT -A INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT

echo Open incoming port 6969 for ssh
# Open port 6969 for ssh
$IPT -A INPUT -p tcp --dport 6969 -j ACCEPT
$IPT -A OUTPUT -p tcp --sport 6969 -j ACCEPT

echo Open incoming port 9090 for cockpit
# Open port 9090 for cockpit
$IPT -A INPUT -p tcp --dport 6969 -j ACCEPT
$IPT -A OUTPUT -p tcp --sport 6969 -j ACCEPT

echo Open port 25 for sendmail
# Allow Sendmail or Postfix
$IPT -A INPUT -p tcp --dport 25 -j ACCEPT
$IPT -A OUTPUT -p tcp --sport 25 -j ACCEPT

echo Open port 465 for secure sendmail
# Allow Sendmail or Postfix
$IPT -A INPUT -p tcp --dport 465 -j ACCEPT
$IPT -A OUTPUT -p tcp --sport 465 -j ACCEPT

echo Allow incoming ICMP ping pong stuff
 # Allow incoming ICMP ping pong stuff
$IPT -A INPUT -p icmp --icmp-type 8 -m state --state NEW,ESTABLISHED,RELATED -m limit --limit 30/sec  -j ACCEPT
$IPT -A INPUT -p icmp -m icmp --icmp-type 3 -m limit --limit 30/sec -j ACCEPT
$IPT -A INPUT -p icmp -m icmp --icmp-type 5 -m limit --limit 30/sec -j ACCEPT
$IPT -A INPUT -p icmp -m icmp --icmp-type 11 -m limit --limit 30/sec -j ACCEPT
 
echo Allow outbound DNS
# Allow outbound DNS
$IPT -A OUTPUT -p udp --dport 53 -j ACCEPT
$IPT -A INPUT -p udp --sport 53 -j ACCEPT

# Security 
# Syn-flood protection:
# $IPT -A FORWARD -p tcp --syn -m limit --limit 1/s -j ACCEPT
# Furtive port scanner:
# $IPT -A FORWARD -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s -j ACCEPT
# Ping of death:
echo Blocking ping of death
$IPT -A FORWARD -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
# Prevent DoS attack
# $IPT -A INPUT -p tcp --dport 80 -m limit --limit 25/minute --limit-burst 100 -j ACCEPT
echo Allow docker
$IPT -A FORWARD -i docker0 -o eth0 -j ACCEPT
$IPT -A FORWARD -i eth0 -o docker0 -j ACCEPT
echo drop and log everything else
# drop and log everything else
# limiting the number of times we log
# Log dropped packets
$IPT -N LOGGING
$IPT -A INPUT -j LOGGING
$IPT -A LOGGING -m limit --limit 25/min --limit-burst 50 -j LOG --log-prefix "IPtables Packet Dropped: " --log-level 5
$IPT -A LOGGING -j DROP

#save IP tables rules to a file
# iptables-save > /root/usefulScripts/iptables/iptables_saved
