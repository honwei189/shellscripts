#!/bin/bash
###
# @description       : Renew whitelist for NginX (map method).
#                      This supports check against x-forward-ip,
#                      to prevent inaccidentaly deny all incoming ips from cloudflare
# @version           : "1.0.0"
# @creator           : Gordon Lim <honwei189@gmail.com>
# @created           : 14/04/2020 13:43:30
 # @last modified     : 28/04/2020 13:26:57
# @last modified by  : Gordon Lim <honwei189@gmail.com>
###

#cron job:
#0 * * * *	sh renew_nginx_whitelist_map.sh >/dev/null 2>&1
#
#nginx config
#e.g:
#    location / {
#        include conf.d/server/check_white_ip.conf;
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
whitelist="/etc/nginx/conf.d/whitelist.conf"  #auto load conf.d/*.conf by nginx
check_white_ip="/etc/nginx/conf.d/server/check_white_ip.conf"

##########

if [ -f $whitelist ];
then
    cat /dev/null > $whitelist
else
    touch $whitelist
fi

#echo "  #set \$realip \$remote_addr;" >> $whitelist
#echo "  #if (\$http_x_forwarded_for ~ \"^(\d+\.\d+\.\d+\.\d+)\") {" >> $whitelist
#echo "  #   set \$realip \$1;" >> $whitelist
#echo "  #}" >> $whitelist
#echo "  " >> $whitelist
#echo "  #fastcgi_param REMOTE_ADDR \$realip;" >> $whitelist
#echo "" >> $whitelist

echo "  map \$http_x_forwarded_for \$real_ip {" >>$whitelist
echo "      ~^(\d+\.\d+\.\d+\.\d+) \$1;" >>$whitelist
echo "      default \$remote_addr;" >>$whitelist
echo "  }" >>$whitelist

echo "" >>$whitelist
echo "  map \$proxy_add_x_forwarded_for \$real_ip {" >>$whitelist
echo "      \"~(?<IP>([0-9]{1,3}\.){3}[0-9]{1,3}),.*\" \$IP;" >>$whitelist
echo "  }" >>$whitelist

echo "" >>$whitelist
echo "  fastcgi_param   REMOTE_ADDR    \$real_ip;" >>$whitelist
echo "  #fastcgi_param   REMOTE_ADDR     \$http_x_forwarded_for;" >>$whitelist

echo "" >>$whitelist
echo "  map \$real_ip \$give_white_ip_access {" >>$whitelist
echo "      default 0;" >>$whitelist

for ip in $ips; do
    echo "      $ip 1;" >>$whitelist
done

for host in $hosts; do
    ip=$(host $host | awk '/has address/ { print $4 }')
    echo "      $ip 1;" >>$whitelist
    echo "$host - $ip"
done

#for ip in $(curl --silent https://www.cloudflare.com/ips-v4)
#do
#    echo "      $ip 1;" >> $whitelist
#done

#for ip in $(curl --silent https://www.cloudflare.com/ips-v6)
#do
#    echo "      $ip 1;" >> $whitelist
#done

echo "  }" >>$whitelist

if [ ! -d /etc/nginx/conf.d/server ]; then
    mkdir -p /etc/nginx/conf.d/server
fi

if [ ! -f $check_white_ip ]; then
    echo "        if (\$give_white_ip_access = 0){" >>$check_white_ip
    echo "            return 404;" >>$check_white_ip
    echo "        }" >>$check_white_ip
fi

#nginx -s reload
service nginx reload
