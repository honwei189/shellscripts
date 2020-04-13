#!/bin/bash
###
 # @description       : Renew whitelist for NginX
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 08/04/2020 16:50:52
 # @last modified     : 12/04/2020 15:13:06
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###

#cron job:
#0 * * * *	sh renew_nginx_whitelist.sh >/dev/null 2>&1
#nginx config
#e.g:
#    location / {
#        include /etc/nginx/conf.d/server/whitelist.conf;
#    }

################################################################
# Hostname allows to access
################################################################
hosts="abc.noip.info
abc.example.com"

################################################################
# IPs allows to access
################################################################
ips="192.168.1.0/24
172.1.1.1"

################################################################
# Whitelist config file  (DO NOT CHANGE)
################################################################
whitelist="/etc/nginx/conf.d/server/whitelist.conf"


##########

cat /dev/null > $whitelist
for ip in $ips
do
    echo "      allow $ip;" >> $whitelist
done

for host in $hosts
do
  ip=$(php -r "echo gethostbyname('${host}');")
  echo "      allow $ip;" >> $whitelist
done


#for ip in $(curl --silent https://www.cloudflare.com/ips-v4)
#do
#    echo "      allow $ip;" >> $whitelist
#done

#for ip in $(curl --silent https://www.cloudflare.com/ips-v6)
#do
#    echo "      allow $ip;" >> $whitelist
#done

echo "      deny all;" >> $whitelist

nginx -s reload
