#!/bin/bash
. /etc/rc.d/init.d/functions

if [ $# -lt 2 ]; then 
    echo "Usage: `basename $0` <JAIL_NAME> IP"
    echo ""
    echo "e.g: `basename $0` http 10.1.1.1"
    echo ""
    echo "e.g: `basename $0` sshd 10.1.1.10"
    echo ""
    exit
fi


fail2ban-client set $1 unbanip "$2"
#firewall-cmd --remove-rich-rule='rule family=ipv4 source address=$2 reject' --permanent
firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='$2' reject"
firewall-cmd --reload

