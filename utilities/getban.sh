#!/bin/bash
. /etc/init.d/functions

# ln -s /prog/get_banned.sh /usr/bin/getban
# chmod +x /usr/bin/getban

fail2ban-client status | grep "Jail list:" | sed "s/ //g" | awk '{split($2,a,",");for(i in a) system("fail2ban-client status " a[i])}' | grep "Status\|IP list"
