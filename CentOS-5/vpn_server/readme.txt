sh install.sh

vim /etc/sysctl.conf
net.ipv4.ip_forward = 1





/sbin/iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
/sbin/iptables -A INPUT -p tcp --dport 47 -j ACCEPT
/sbin/iptables -A INPUT -p gre -j ACCEPT


iptables save
iptables restart