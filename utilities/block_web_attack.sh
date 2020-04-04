#!/bin/bash
# chmod 700 block.sh

#1 = fireall-cmd, 2 = iptables
firewall=1
restart_fw=0;
local_ip="127.0.0.1
43.228.125.46
120.50.57.234
120.50.54.242
120.50.54.243
120.50.54.244
120.50.54.245"

if [ ! "$1" ] ; then
    echo "Usage: `basename $0` <WEB_SERVER_LOG_PATH>"
    echo ""
    echo "e.g: `basename $0` /var/log/nginx"
    echo ""
    exit
fi


cmd="";
FILES=$(find $1 -type f -name '*.access.log' -o -name 'access.log')


if [ -f "$1/blacklist.txt" ]; then
  rm -rf $1/blacklist.txt
fi

touch $1/blacklist.txt

checkWhiteIP () {
    ip=$1;

    for i in $local_ip
    do
        if [ "$ip" == "$i" ]; then
            echo 1
            return 1;
        fi
    done

    echo 0
    return 0;
}

for file in $FILES
do
  echo $file;
  #(cat access.log  | awk '/Status : 4*/ { print $4, $21 }'g | sort | uniq -c | sort -n) | while read line
  (tail -100 $file | awk '/Status : 4/ { print $0 }'g | sort | uniq -c | sort -n) | while read line
  #(cat access.log  | sort | uniq -c | sort -n) | while read line
  do
     # do something with $line here
    #count=$(echo $line | cut -d' ' -f1)
    #ip=$(echo $line | cut -d' ' -f2)
    #status=$(echo $line | cut -d' ' -f3)
  
    #echo "Ban IP : $ip";
    #echo $line | awk -F "X-Forwarded IP :" '{print $2}'
    ip=$(echo $line | grep -P 'X-Forwarded IP :(.*)(?=, Country)' -o)
    ip=$(echo $ip | awk '/\"/ { print $4 }'g | sed -e 's/^"//' -e 's/"$//' | tr -d '\r\n')
  
    count=$(echo $line | cut -d' ' -f1)
  
    origin=$(echo $line | grep -P 'From:(.*)(?=, URL)' -o)
    origin=$(echo $origin | awk '/:/ { print $2 }'g | sed -e 's/^"//' -e 's/"$//' | tr -d '\r\n')
    origin_baseip2=`echo $origin | cut -d"." -f1-2`
    origin_baseip2=$(echo $origin_baseip2".0.0")
    origin_baseip=`echo $origin | cut -d"." -f1-3`
    origin_baseip=$(echo $origin_baseip".0")
  
    if [ "$ip" == "-" ]; then
      ip=$origin
      origin=""
    fi

    checklocal=$( checkWhiteIP "$ip" )

    if [ "$checklocal" == "0" ]; then
        status=$(echo $line | grep -P 'Status : (.*)(?=, Bytes)' -o)
        status=$(echo $status | awk '/:/ { print $3 }'g | tr -d '\r\n' | tr -d '[:space:]')
        ip_baseip=`echo $ip | cut -d"." -f1-2`
        ip_baseip=$(echo $ip_baseip".0.0")
        baseip=`echo $ip | cut -d"." -f1-3`
        baseip=$(echo $baseip".0")
        ip6_baseip=""
    
        #if [ "$status" != "301" ] && [ "$count" -gt 1 ]; then
        #if [ "$status" != "200" ] || [ "$status" != "301" ]; then
        if [ "$status" == "400" ] || [ "$status" == "402" ] || [ "$status" == "403" ] || [ "$status" == "405" ] || [ "$status" == "406" ] ||  [ "$status" == "407" ] || [ "$status" == "410" ] || [ "$status" == "401" ] || [ "$status" == "444" ]; then
        echo "Tried : $count, Ban IP : $baseip $origin, status : $status";
    
        #echo "fgrep -c \"$ip_baseip\" /etc/nginx/cloudflare.conf"
    
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            #cmd="firewall-cmd --permanent --add-rich-rule=\"rule family='ipv4' source address='$ip' reject\""
            cmd="firewall-cmd --permanent --ipset=networkblock --add-entry=$ip"
            #firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip' reject"
        else
            ip6_baseip=`echo $ip | cut -d":" -f1-2`
            ip6_baseip=$(echo $ip6_baseip"::")
            cmd="firewall-cmd --permanent --add-rich-rule=\"rule family='ipv6' source address='$ip' reject\""
            #firewall-cmd --permanent --add-rich-rule="rule family='ipv6' source address='$ip' reject"
        fi
    
        if [ "$ip6_baseip" == "" ]; then
            found=`fgrep -c "$ip_baseip" /etc/nginx/cloudflare.conf`
            found2=`fgrep -c "$ip" /etc/nginx/whitelist.txt`
    
            if [ $found -eq 0 ] && [ $found2 -eq 0 ] ; then
            echo $baseip;
            echo $baseip >> /var/log/nginx/blacklist.txt
            fi
        else
            found=`fgrep -c "$ip6_baseip" /etc/nginx/cloudflare.conf`
            if [ $found -eq 0 ]; then
            #echo $ip6_baseip;
            echo $ip6_baseip >> /var/log/nginx/blacklist.txt
            fi
        fi
    
        if [ "$origin" != "" ]; then
            #echo "fgrep -c \"$origin_baseip\" /etc/nginx/cloudflare.conf"
            found=`fgrep -c "$origin_baseip2" /etc/nginx/cloudflare.conf`
            found2=`fgrep -c "$origin_ip" /etc/nginx/whitelist.txt`
    
            if [ $found -eq 0 ] && [ $found2 -eq 0 ] ; then
            #echo $origin_baseip;
            echo $origin_baseip >> /var/log/nginx/blacklist.txt
            fi
    
            #fgrep -c "162.158.0.0" /etc/nginx/cloudflare.conf
        fi
    
        #echo $ip >> /etc/hosts.deny
        #echo $cmd;
        fi
    fi
  done
  
  (cat /var/log/nginx/blacklist.txt | sort | uniq) > /var/log/nginx/blacklist2.txt && rm -rf /var/log/nginx/blacklist.txt && mv /var/log/nginx/blacklist2.txt /var/log/nginx/blacklist.txt
  
  (cat /var/log/nginx/blacklist.txt) | while read ip
  do
    set -f  # avoid globbing (expansion of *).
    array=(${ip//,/ })
    for i in "${!array[@]}"
    do
      if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then
        ip=$(echo $ip | tr -d '::' | tr -d '[:space:]');
        ip=`echo $ip | cut -d"." -f1-3`
        ip=$(echo $ip".0")
      fi

      ip2=$(echo "${array[i]}" | tr -d '::' | tr -d '[:space:]');
      host=`host $ip2`

      case "$host" in
        *google.com*)
          check=`fgrep -c "google:${ip2}" /etc/nginx/whitelist.txt`
          if [ $check -eq 0 ] ; then
            echo "google:${ip2}" >> /etc/nginx/whitelist.txt && sed -i "s|#2001:db8::/32      1;|#2001:db8::/32      1;\n    $ip2		0; #google|g" /etc/nginx/maps/whitelisted_ip.conf
          fi
        ;;

        *googlebot.com*)
          check=`fgrep -c "googlebot:${ip2}" /etc/nginx/whitelist.txt`
          if [ $check -eq 0 ] ; then
            echo "googlebot:${ip2}" >> /etc/nginx/whitelist.txt && sed -i "s|#2001:db8::/32      1;|#2001:db8::/32      1;\n    $ip2		0; #googlebot|g" /etc/nginx/maps/whitelisted_ip.conf
          fi
        ;;

        *yahoo.com*)
          check=`fgrep -c "yahoo:${ip2}" /etc/nginx/whitelist.txt`
          if [ $check -eq 0 ] ; then
            echo "yahoo:${ip2}" >> /etc/nginx/whitelist.txt && sed -i "s|#2001:db8::/32      1;|#2001:db8::/32      1;\n    $ip2		0; #yahoo|g" /etc/nginx/maps/whitelisted_ip.conf
          fi
        *;;

        *bing.com*)
          check=`fgrep -c "bing:${ip2}" /etc/nginx/whitelist.txt`
          if [ $check -eq 0 ] ; then
            echo "bing:${ip2}" >> /etc/nginx/whitelist.txt && sed -i "s|#2001:db8::/32      1;|#2001:db8::/32      1;\n    $ip2		0; #bing|g" /etc/nginx/maps/whitelisted_ip.conf
          fi
        *;;

        *msn.com*)
          check=`fgrep -c "msn:${ip2}" /etc/nginx/whitelist.txt`
          if [ $check -eq 0 ] ; then
            echo "msn:${ip2}" >> /etc/nginx/whitelist.txt && sed -i "s|#2001:db8::/32      1;|#2001:db8::/32      1;\n    $ip2		0; #msn|g" /etc/nginx/maps/whitelisted_ip.conf
          fi
        ;;
      esac

      
      found=`fgrep -c "$ip" /etc/nginx/blacklist.txt`
      found2=`fgrep -c "$ip" /etc/nginx/whitelist.txt`

      if [ $found -eq 0 ] && [ $found2 -eq 0 ] ; then
        restart_fw=1;

        #array=$(echo $array | tr -d '::' | tr -d '[:space:]');
        #ip="${array[i]}"

        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
          if [ $firewall -eq 1 ]; then
            firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip/24' reject" >/dev/null 2>&1
          else
            iptables -A INPUT -s $ip/24 -j DROP
          fi

          #fail2ban-client set http banip $ip/24
        else
          if [ $firewall -eq 1 ]; then
            firewall-cmd --permanent --add-rich-rule="rule family='ipv6' source address='$ip/32' reject" >/dev/null 2>&1
          else
            ip6tables -A INPUT -s $ip/32 -j DROP
          fi

          #fail2ban-client set http banip $ip/32
          #echo "$i=>${array[i]}, $ip"
        
        fi

        echo $ip >> /etc/nginx/blacklist.txt

      fi

    done

  done
  
done

#if [ $restart_fw -eq 1 ]; then
    file="/etc/nginx/whitelist.txt"
    if [ -n $(find . -name $file -mmin +1 2>/dev/null) ]; then
        if [ $firewall -eq 1 ]; then
            firewall-cmd --reload
        else
            service iptables save
        fi
    fi
#fi

#if [ $restart_fw -eq 1 ]; then
#  if [ $firewall -eq 1 ]; then
#    firewall-cmd --reload
#  else
#    service iptables save
#  fi
#fi
