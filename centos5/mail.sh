# /bin/bash

if [[ $EUID -ne 0 ]]; then
   AR=$(echo -e "You are not a root user")
else
   AR=$(cat /var/log/secure | grep -E '(Accepted|SUCCEEDED)' | tail -n 1) 
fi
AT=$(echo -e "\n")
AS=$(last | head -n 1)
AK=${AR}"\n"${AS}
echo -e "$AK" | mail -s "ssh login on myVPS" sdsunjay73@yahoo.com
