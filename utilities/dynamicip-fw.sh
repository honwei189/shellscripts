#!/bin/sh
###
# @description       : Add dynamic host / IP into firewall trusted list allows SSH into server without any restriction
#                      Add dynamic host into SSHD configuration allows SSH into server with password
#                      Applicable for CentOS based system ( v7.x, v8.x, Oracle Linux 8.x, AlmaLinux 8.x, RockyLinux 8.x )
# @installation      : ln -s dynamicip-fw.sh /usr/bin/dynamicip-fw
#                      or;
#                      mv dynamicip-fw.sh /usr/bin/dynamicip-fw
#                      chmod +x /usr/bin/dynamicip-fw
#                      echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
#                      echo "Include /etc/ssh/hosts/*.conf" >> /etc/ssh/sshd_config
#                      crontab (automatically run hourly):  0 * * * * /usr/bin/dynamicip-fw refresh >/dev/null 2>&1
# @usage             : dynamicip-fw add HOSTNAME
#                      dynamicip-fw del HOSTNAME
#                      dynamicip-fw delete HOSTNAME
#                      dynamicip-fw refresh
# @version           : "1.0.0"
# @creator           : Gordon Lim <honwei189@gmail.com>
# @created           : 25/04/2020 12:27:17
# @last modified     : 04/10/2022 09:57:00
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
OS_VER=$(cat /etc/redhat-release | tr -dc '0-9.' | cut -d \. -f1)
##########

# restart_fw=0

if [ ! -d $DYNAMIC_IP_PATH ]; then
    mkdir -p $DYNAMIC_IP_PATH
fi

if [ "$OS_VER" -ge '8' ]; then
    if [ ! -d /etc/ssh/hosts ]; then
        mkdir -p /etc/ssh/hosts
    fi
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
    if [ "$1" == "" ]; then
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
            #ip=$(host $1 | awk '/has address/ { print $4 }')
            ip=$(nslookup $1 8.8.8.8 | awk '/Address: / { print $2 }')
        fi

        echo "$1:$ip" >>$IP_LIST

        if [ "$OS_VER" == "7" ]; then
            echo "$ip	$1" >>/etc/hosts

            echo "Match Host $1
	PasswordAuthentication yes" >>"/etc/ssh/sshd_config"
        else
            echo "Match Host $ip
	PasswordAuthentication yes" >"/etc/ssh/hosts/$1.conf"
        fi

        service sshd reload

        # firewall-cmd --permanent --add-source=$ip --zone=trusted > /dev/null 2>&1
        # #firewall-cmd --refresh > /dev/null 2>&1
        # firewall-cmd --reload > /dev/null 2>&1

        firewall-cmd --add-source=$ip --zone=trusted >/dev/null 2>&1

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
    if [ "$1" == "" ]; then
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

        if [ "$OS_VER" == "7" ]; then
            sed --in-place "/$1/d" /etc/hosts
            sed --in-place "/Match Host $1/,+2d" /etc/ssh/sshd_config
        else
            rm -rf "/etc/ssh/hosts/$1.conf"
        fi

        service sshd reload

        if [ $is_ip -eq 1 ]; then
            ip=$1
        else
            #ip=$(host $1 | awk '/has address/ { print $4 }')
            #ip=$(nslookup $1 8.8.8.8 | awk '/Address: / { print $2 }')
            ip=$(dig +short $1 @8.8.8.8)
        fi

        # firewall-cmd --permanent --remove-source=$ip --zone=trusted > /dev/null 2>&1
        ##firewall-cmd --refresh > /dev/null 2>&1
        #firewall-cmd --reload > /dev/null 2>&1
        firewall-cmd --remove-source=$ip --zone=trusted >/dev/null 2>&1

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

list() {
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ Dynamic HOSTS list ]"
    $SETCOLOR_NORMAL
    echo ""

    for host in $(cat $IP_LIST); do
        hostname=$(echo $host | cut -d":" -f1)
        #ip=$(echo $host | cut -d":" -f2)
        ip=$(nslookup $host 8.8.8.8 | awk '/Address: / { print $2 }')
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
        #ip=$(host $host | awk '/has address/ { print $4 }')
        ip=$(nslookup $host 8.8.8.8 | awk '/Address: / { print $2 }')
        #ip=$(dig +short $host @8.8.8.8)
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
            # restart_fw=1
        else
            old_ip=$(echo $find | cut -d":" -f2)

            if [ "$find" != "$host:$ip" ]; then
                cmd="sed -i 's/${find}/$host:$ip/g' $IP_LIST"
                eval "$cmd"

                if [ "$OS_VER" == "7" ]; then
                    sed --in-place "/$host/d" /etc/hosts
                    echo "$ip	$host" >>/etc/hosts
                else
                    echo "Match Host $ip
    PasswordAuthentication yes" >"/etc/ssh/hosts/$host.conf"
                fi

                service sshd reload

                #old_ip=$(echo $old_ip | cut -d"." -f1-3)
                #old_ip=$(echo $old_ip".0")
                #base_ip=$(echo $ip | cut -d"." -f1-3)
                #base_ip=$(echo $base_ip".0")

                fw=$(firewall-cmd --zone=trusted --list-sources | grep "$old_ip")

                if [ "$fw" != "" ]; then
                    # firewall-cmd --permanent --remove-source=$old_ip --zone=trusted > /dev/null 2>&1
                    firewall-cmd --remove-source=$old_ip --zone=trusted >/dev/null 2>&1
                    # restart_fw=1
                fi

                fw=$(firewall-cmd --zone=trusted --list-sources | grep "$ip")

                if [ "$fw" == "" ]; then
                    # firewall-cmd --permanent --add-source=$ip --zone=trusted > /dev/null 2>&1
                    firewall-cmd --add-source=$ip --zone=trusted >/dev/null 2>&1
                    # restart_fw=1
                fi
            else
                fw=$(firewall-cmd --zone=trusted --list-sources | grep "$ip")

                if [ "$fw" == "" ]; then
                    # firewall-cmd --permanent --add-source=$ip --zone=trusted > /dev/null 2>&1
                    firewall-cmd --add-source=$ip --zone=trusted >/dev/null 2>&1
                    # restart_fw=1

                    # oldfw=$(firewall-cmd --zone=trusted --list-sources | grep "$old_ip")

                    # if [ "$oldfw" != "" ]; then
                    #     firewall-cmd --remove-source=$old_ip --zone=trusted > /dev/null 2>&1
                    # fi
                fi
            fi
        fi

    done

    # if [ $restart_fw -eq 1 ]; then
    #     sudo firewall-cmd --reload
    # fi
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
