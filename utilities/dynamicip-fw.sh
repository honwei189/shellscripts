#!/bin/sh
###
 # @description       : Add dynamic host / IP into firewall trusted list allows connecting server without any restriction.
 #                      Applicable for CentOS 7 and above only
 # @installation      : ln -s dynamicip-fw.sh /usr/bin/dynamicip-fw
 #                      or;
 #                      mv dynamicip-fw.sh /usr/bin/dynamicip-fw
 #                      chmod +x /usr/bin/dynamicip-fw
 #                      crontab (automatically run hourly):  0 * * * * /usr/bin/dynamicip-fw refresh >/dev/null 2>&1
 # @usage             : dynamicip-fw add HOSTNAME
 #                      dynamicip-fw del HOSTNAME
 #                      dynamicip-fw delete HOSTNAME
 #                      dynamicip-fw refresh
 # @version           : "1.0.0"
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 25/04/2020 12:27:17
 # @last modified     : 29/05/2020 16:50:38
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
###

# Source function library.
# . /etc/init.d/functions

################################################################
# (DO NOT CHANGE IT)
################################################################
DYNAMIC_IP_PATH="/etc/dynamicip"
HOSTS="$DYNAMIC_IP_PATH/hosts"
IP_LIST="$DYNAMIC_IP_PATH/ips"

##########

restart_fw=0

if [ ! -d $DYNAMIC_IP_PATH ]; then
    mkdir -p $DYNAMIC_IP_PATH
fi

if [ ! -f $HOSTS ]; then
    touch $HOSTS
fi

if [ ! -f $IP_LIST ]; then
    touch $IP_LIST
fi

#MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

add() {
    if [ "$1" == "" ];then
        help
        exit 1
    fi

    is_ip=0

    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        is_ip=1
    fi

    find=$(cat $HOSTS | grep "$1")
    if [ "$find" == "" ]; then
        echo "$1" >>$HOSTS

        if [ $is_ip -eq 1 ]; then
            ip=$1
            is_ip=1
        else
            ip=$(host $1 | awk '/has address/ { print $4 }')
        fi

        echo "$1:$ip" >>$IP_LIST
        
        firewall-cmd --permanent --add-source=$ip --zone=trusted > /dev/null 2>&1
        #firewall-cmd --refresh > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1

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
        echo " has been granted into trusted network successfully"
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

delete() {
    if [ "$1" == "" ];then
        help
        exit 1
    fi

    is_ip=0

    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        is_ip=1
    fi

    find=$(cat $HOSTS | grep "$1")
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
        sed --in-place "/$1/d" $HOSTS
        sed --in-place "/$1/d" $IP_LIST

        if [ $is_ip -eq 1 ]; then
            ip=$1
        else
            ip=$(host $1 | awk '/has address/ { print $4 }')
        fi
        
        firewall-cmd --permanent --remove-source=$ip --zone=trusted > /dev/null 2>&1
        #firewall-cmd --refresh > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1

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
        echo " has been removed from trusted network successfully"
        $SETCOLOR_NORMAL
        echo ""
        echo ""
    fi
}

list(){
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ Dynamic HOSTS list ]"
    $SETCOLOR_NORMAL
    echo ""
    
    for host in $(cat $IP_LIST); do
        hostname=$(echo $host | cut -d":" -f1)
        ip=$(echo $host | cut -d":" -f2)
        $SETCOLOR_FAILURE
        echo -en "$hostname \t\t "

        if [ ! "$hostname" == "$ip" ]; then
            $SETCOLOR_NORMAL
            echo -en ""
            $SETCOLOR_SUCCESS
            echo "$ip"
        fi
        
        $SETCOLOR_NORMAL
    done
    
    echo ""
    echo ""
}

refresh() {
    for host in $(cat $HOSTS); do
        ip=$(host $host | awk '/has address/ { print $4 }')
        find=$(cat $IP_LIST | grep "$host")
        
        if [ "$find" == "" ]; then
            echo "$host:$ip" >>$IP_LIST
            # echo ""
            # echo -n "Hostname "
            # $SETCOLOR_FAILURE
            # echo -n "$1 - $ip"
            # $SETCOLOR_SUCCESS
            # echo " has been granted into trusted network"
            # $SETCOLOR_NORMAL
            # echo ""
            # echo ""
            restart_fw=1
        else
            if [ "$find" != "$host:$ip" ]; then
                cmd="sed -i 's/${find}/$host:$ip/g' $IP_LIST"
                eval "$cmd"

                old_ip=$(echo $find | cut -d":" -f2)
                #old_ip=$(echo $old_ip | cut -d"." -f1-3)
                #old_ip=$(echo $old_ip".0")
                #base_ip=$(echo $ip | cut -d"." -f1-3)
                #base_ip=$(echo $base_ip".0")

                fw=$(firewall-cmd --zone=trusted --list-sources | grep "$old_ip")

                if [ "$fw" != "" ]; then
                    firewall-cmd --permanent --remove-source=$old_ip --zone=trusted > /dev/null 2>&1
                    restart_fw=1
                fi

                fw=$(firewall-cmd --zone=trusted --list-sources | grep "$ip")

                if [ "$fw" == "" ]; then
                    firewall-cmd --permanent --add-source=$ip --zone=trusted > /dev/null 2>&1
                    restart_fw=1
                fi
            fi
        fi

    done

    if [ $restart_fw -eq 1 ]; then
        sudo firewall-cmd --reload
    fi
}

help() {
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ Add dynamic host / IP into firewall trusted list allows connecting server without any restriction ]"
    $SETCOLOR_NORMAL
    echo ""

    $SETCOLOR_FAILURE
    echo "Usage : "
    echo ""
    echo -n "$0 "
    $SETCOLOR_SUCCESS
    echo "{add|del|delete|list|refresh}"

    echo ""
    echo -e "add \t\t- Add dynamic hostname or ip"
    echo -e "del \t\t- Delete dynamic hostname or ip from trusted list"
    echo -e "delete \t\t- Delete dynamic hostname or ip from trusted list"
    echo -e "list \t\t- List all registered dynamic HOSTS"
    echo -e "refresh \t- Refresh all dynamic hostnames and update latest IPs to trusted list"

    echo ""
    echo ""
    $SETCOLOR_FAILURE
    echo "Example : "
    echo ""
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " add "
    $SETCOLOR_NORMAL
    echo "abc.ddns.net"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " delete "
    $SETCOLOR_NORMAL
    echo "abc.ddns.net"
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
    echo " refresh"
    $SETCOLOR_NORMAL
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
list)
    list
    ;;
refresh)
    refresh
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
