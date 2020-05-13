#!/bin/bash
###
 # @description       : Grant certains IPs / dynamic hosts name to access some restriction site.
 #                      And to renew whitelist for NGINX (map method).
 #                      This supports check against x-forward-ip,
 #                      to prevent inaccidentaly deny all incoming ips from cloudflare
 # @version           : "1.1.0"
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 14/04/2020 13:43:30
 # @last modified     : 13/05/2020 16:56:49
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
###

################################# INSTALLATION ################################
# Make sure that "/usr/bin/nginx-whitelist" doesn't exist
#
# ln -s update-nginx-whitelist.sh /usr/bin/nginx-whitelist
# or;
# mv update-nginx-whitelist.sh /usr/bin/nginx-whitelist
#
# chmod +x /usr/bin/nginx-whitelist
#
# cron job:
# 0 * * * *	/usr/bin/nginx-whitelist update >/dev/null 2>&1
#
# nginx config
# e.g:
#    location / {
#        include conf.d/server/check_white_ip.conf;
#    }
#
###############################################################################


################################################################
# (DO NOT CHANGE)
################################################################
NGINX_PATH="/etc/nginx"
NGINX_WHITELIST="$NGINX_PATH/whitelist"

################################################################

################################################################
# Whitelist config file  (DO NOT CHANGE)
################################################################
WHITELIST_CONF_MAP_FILE="$NGINX_PATH/conf.d/whitelist.conf" #auto load conf.d/*.conf by nginx
NGINX_CHECK_FROM_WHITELIST="$NGINX_PATH/conf.d/server/check_white_ip.conf"

##########

if [ ! -d $NGINX_WHITELIST ]; then
    mkdir $NGINX_WHITELIST
fi

if [ -f $NGINX_WHITELIST/hosts ]; then
    hosts=$(cat $NGINX_WHITELIST/hosts)
else
    touch $NGINX_WHITELIST/hosts
    echo "#################################################################" >>$NGINX_WHITELIST/hosts
    echo "# Hostname allows to access" >>$NGINX_WHITELIST/hosts
    echo "#################################################################" >>$NGINX_WHITELIST/hosts
    echo "# Example:" >>$NGINX_WHITELIST/hosts
    echo "# " >>$NGINX_WHITELIST/hosts
    echo "# abc.noip.info" >>$NGINX_WHITELIST/hosts
    echo "# abc.example.com" >>$NGINX_WHITELIST/hosts
    echo "# " >>$NGINX_WHITELIST/hosts
    echo "" >>$NGINX_WHITELIST/hosts
    echo "" >>$NGINX_WHITELIST/hosts
    hosts=
fi

if [ -f $NGINX_WHITELIST/ip ]; then
    ips=$(cat $NGINX_WHITELIST/ip)
else
    touch $NGINX_WHITELIST/ip
    echo "#################################################################" >>$NGINX_WHITELIST/ip
    echo "# IPs allows to access" >>$NGINX_WHITELIST/ip
    echo "#################################################################" >>$NGINX_WHITELIST/ip
    echo "# Example:" >>$NGINX_WHITELIST/ip
    echo "# " >>$NGINX_WHITELIST/ip
    echo "# 192.168.1.0/24" >>$NGINX_WHITELIST/ip
    echo "# 172.1.1.1" >>$NGINX_WHITELIST/ip
    echo "" >>$NGINX_WHITELIST/ip
    echo "" >>$NGINX_WHITELIST/ip
    ips=
fi

#MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

add() {
    if [ "$1" == "" ]; then
        help
        exit 1
    fi

    is_ip=0

    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then
        is_ip=1
    fi

    if [ $is_ip -eq 1 ]; then
        find=$(cat $NGINX_WHITELIST/ip | egrep -v '^(;|#|//|$)' | grep "$1")
    else
        find=$(cat $NGINX_WHITELIST/hosts | egrep -v '^(;|#|//|$)' | grep "$1")
    fi

    if [ "$find" == "" ]; then
        if [ $is_ip -eq 1 ]; then
            echo "$1" >>$NGINX_WHITELIST/ip
        else
            echo "$1" >>$NGINX_WHITELIST/hosts
        fi

        echo ""

        if [ $is_ip -eq 1 ]; then
            echo -n "IP "
            $SETCOLOR_FAILURE
            echo -n "$1"
        else
            echo -n "Hostname "
            $SETCOLOR_FAILURE
            echo -n "$1 - $ip"
        fi

        $SETCOLOR_SUCCESS
        echo " has been added into NGINX whitelist successfully"
        $SETCOLOR_NORMAL
        echo ""
        echo ""
    else
        echo ""

        if [ $is_ip -eq 1 ]; then
            echo -n "IP "
        else
            echo -n "Hostname "
        fi

        $SETCOLOR_FAILURE
        echo -n "$1"
        $SETCOLOR_SUCCESS
        echo " already exists"
        $SETCOLOR_NORMAL
        echo ""
        echo ""
    fi
}

update() {
    if [ -f $WHITELIST_CONF_MAP_FILE ]; then
        cat /dev/null >$WHITELIST_CONF_MAP_FILE
    else
        touch $WHITELIST_CONF_MAP_FILE
    fi

    hosts=$(cat $NGINX_WHITELIST/hosts | egrep -v '^(;|#|//|$)')
    ips=$(cat $NGINX_WHITELIST/ip | egrep -v '^(;|#|//|$)')

    #echo "  #set \$realip \$remote_addr;" >> $WHITELIST_CONF_MAP_FILE
    #echo "  #if (\$http_x_forwarded_for ~ \"^(\d+\.\d+\.\d+\.\d+)\") {" >> $WHITELIST_CONF_MAP_FILE
    #echo "  #   set \$realip \$1;" >> $WHITELIST_CONF_MAP_FILE
    #echo "  #}" >> $WHITELIST_CONF_MAP_FILE
    #echo "  " >> $WHITELIST_CONF_MAP_FILE
    #echo "  #fastcgi_param REMOTE_ADDR \$realip;" >> $WHITELIST_CONF_MAP_FILE
    #echo "" >> $WHITELIST_CONF_MAP_FILE

    echo "  map \$http_x_forwarded_for \$real_ip {" >>$WHITELIST_CONF_MAP_FILE
    echo "      ~^(\d+\.\d+\.\d+\.\d+) \$1;" >>$WHITELIST_CONF_MAP_FILE
    echo "      default \$remote_addr;" >>$WHITELIST_CONF_MAP_FILE
    echo "  }" >>$WHITELIST_CONF_MAP_FILE

    echo "" >>$WHITELIST_CONF_MAP_FILE
    echo "  map \$proxy_add_x_forwarded_for \$real_ip {" >>$WHITELIST_CONF_MAP_FILE
    echo "      \"~(?<IP>([0-9]{1,3}\.){3}[0-9]{1,3}),.*\" \$IP;" >>$WHITELIST_CONF_MAP_FILE
    echo "  }" >>$WHITELIST_CONF_MAP_FILE

    echo "" >>$WHITELIST_CONF_MAP_FILE
    echo "  fastcgi_param   REMOTE_ADDR    \$real_ip;" >>$WHITELIST_CONF_MAP_FILE
    echo "  #fastcgi_param   REMOTE_ADDR     \$http_x_forwarded_for;" >>$WHITELIST_CONF_MAP_FILE

    echo "" >>$WHITELIST_CONF_MAP_FILE
    echo "  map \$real_ip \$give_white_ip_access {" >>$WHITELIST_CONF_MAP_FILE
    echo "      default 0;" >>$WHITELIST_CONF_MAP_FILE

    for ip in $ips; do
        echo "      $ip 1;" >>$WHITELIST_CONF_MAP_FILE
    done

    for host in $hosts; do
        ip=$(host $host | awk '/has address/ { print $4 }')
        echo "      $ip 1;" >>$WHITELIST_CONF_MAP_FILE
        echo "$host - $ip"
    done

    #for ip in $(curl --silent https://www.cloudflare.com/ips-v4)
    #do
    #    echo "      $ip 1;" >> $WHITELIST_CONF_MAP_FILE
    #done

    #for ip in $(curl --silent https://www.cloudflare.com/ips-v6)
    #do
    #    echo "      $ip 1;" >> $WHITELIST_CONF_MAP_FILE
    #done

    echo "  }" >>$WHITELIST_CONF_MAP_FILE

    if [ ! -d $NGINX_PATH/conf.d/server ]; then
        mkdir -p $NGINX_PATH/conf.d/server
    fi

    if [ ! -f $NGINX_CHECK_FROM_WHITELIST ]; then
        echo "        if (\$give_white_ip_access = 0){" >>$NGINX_CHECK_FROM_WHITELIST
        echo "            return 404;" >>$NGINX_CHECK_FROM_WHITELIST
        echo "        }" >>$NGINX_CHECK_FROM_WHITELIST
    fi

    #nginx -s reload
    service nginx reload
}

delete() {
    if [ "$1" == "" ]; then
        help
        exit 1
    fi

    is_ip=0

    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then
        is_ip=1
    fi

    if [ $is_ip -eq 1 ]; then
        find=$(cat $NGINX_WHITELIST/ip | egrep -v '^(;|#|//|$)' | grep "$1")
    else
        find=$(cat $NGINX_WHITELIST/hosts | egrep -v '^(;|#|//|$)' | grep "$1")
    fi

    if [ "$find" == "" ]; then
        echo ""

        if [ $is_ip -eq 1 ]; then
            echo -n "IP "
        else
            echo -n "Hostname "
        fi

        $SETCOLOR_FAILURE
        echo -n "$1"
        $SETCOLOR_SUCCESS
        echo " doesn't exists"
        $SETCOLOR_NORMAL
        echo ""
    else
        if [ $is_ip -eq 1 ]; then
            sed --in-place "/$1/d" $NGINX_WHITELIST/ip
        else
            sed --in-place "/$1/d" $NGINX_WHITELIST/hosts
        fi

        echo ""
        if [ $is_ip -eq 1 ]; then
            echo -n "IP "
            $SETCOLOR_FAILURE
            echo -n "$1"
        else
            echo -n "Hostname "
            $SETCOLOR_FAILURE
            echo -n "$1"
        fi

        $SETCOLOR_SUCCESS
        echo " has been removed from nginx whitelist successfully"
        $SETCOLOR_NORMAL
        echo ""
        echo ""
    fi
}

list() {
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ NGINX whitelist ]"
    $SETCOLOR_NORMAL
    echo ""
    echo ""
    
    echo "IPs :"
    echo "----------------------------------------------------------------"

    for host in $(cat $NGINX_WHITELIST/ip | egrep -v '^(;|#|//|$)'); do
        $SETCOLOR_FAILURE
        
        $SETCOLOR_NORMAL
        echo -en ""
        $SETCOLOR_SUCCESS
        echo "$host"
        
        $SETCOLOR_NORMAL
    done

    echo ""
    echo ""
    
    echo "Dynamic host names :"
    echo "----------------------------------------------------------------"

    for host in $(cat $NGINX_WHITELIST/hosts | egrep -v '^(;|#|//|$)'); do
        $SETCOLOR_FAILURE
        
        $SETCOLOR_NORMAL
        echo -en ""
        $SETCOLOR_SUCCESS
        echo "$host"
        
        $SETCOLOR_NORMAL
    done
    
    echo ""
    echo ""
}

help() {
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ Add IP / dynamic host name into NGINX whitelist ]"
    $SETCOLOR_NORMAL
    echo ""

    $SETCOLOR_FAILURE
    echo "Usage : "
    echo ""
    echo -n "$0 "
    $SETCOLOR_SUCCESS
    echo "{add|del|delete|update|list}"

    echo ""
    echo -e "add \t\t- Add IP / dynamic host name into whitelist"
    echo -e "del \t\t- Delete IP / dynamic host name from whitelist"
    echo -e "delete \t\t- Delete IP / dynamic host name from whitelist"
    echo -e "update \t\t- Update dynamic host name IP"
    echo -e "list \t\t- List all whitelist IP and dynamic host names"

    echo ""
    echo ""
    $SETCOLOR_FAILURE
    echo "Example : "
    echo ""
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " add "
    $SETCOLOR_NORMAL
    echo "127.0.0.1"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " delete "
    $SETCOLOR_NORMAL
    echo "abc.noip.info"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " delete "
    $SETCOLOR_NORMAL
    echo "172.1.1.1"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo " list"
    $SETCOLOR_NORMAL
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " list "
    echo ""
}

#clear

case "$1" in
add)
    add $2
    ;;
del)
    delete $2
    ;;
delete)
    delete $2
    ;;
update)
    update $2
    ;;
list)
    list $2
    ;;
-h)
    help
    ;;
-help)
    help
    ;;
--help)
    help
    ;;
*)
    help
    ;;
esac

exit 0
