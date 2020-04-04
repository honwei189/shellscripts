###
 # @description       : System maintenance script
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @last modified     : 03/04/2020 14:48:04
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###
#!/bin/sh
. /etc/rc.d/init.d/functions

clear

function mem_used(){
  #PER=`ps aux | awk '{sum +=$4}; END {print sum}'`
  #USED=`free -t | grep "buffers/cache" | awk '{print $4/($3+$4) * 100}'`
  #USED=`free | awk '/buffers\/cache/{print $4/($3+$4) * 100.0;}'`

  PER=`printf "%.0f" $(free -t | grep "buffers/cache" | awk '{print 100-($4/($3+$4) * 100)}')`
  #a1=`ls -la /proc/kcore | awk '{print $5}' | tr -d ''`;echo $(($a1/1024/1024))MB;
  a1=`ls -la /proc/kcore | awk '{print $5}' | tr -d ''`;
  echo "Total RAM : "$(($a1/1024)) GB;

  python="python"
  type -P python3 >/dev/null 2>&1 && python="python3"

  freemem=$(echo -e 'import re\nmatched=re.search(r"^MemTotal:\s+(\d+)",open("/proc/meminfo").read())\nprint(int(matched.groups()[0])/(1024.**2))' | $python)
  echo "Total RAM : $freemem GB"
  echo "Pre-allocated Buffer Memory Used: $PER%"

  TOT=`cat /proc/meminfo | grep MemTotal: | awk '{print $2}'`
  USED=`cat /proc/meminfo | grep Active: | awk '{print $2}'`
  BUFFER=`cat /proc/meminfo | grep Buffers: | awk '{print $2}'`
  FREE=$[$TOT-$USED]
  LOG=/tmp/mem_monitor.log
  echo > $LOG
  SEND=0
  HOST="$(hostname)"


  if [ "$USED" -gt "0" ]; then
    #USEDPERC=$(( ${USED#0} *100 / $(( ${TOT#0} )) ))
    USEDPERC=$(( (( ${USED#0} - ${BUFFER#0} )) *100 / $(( ${TOT#0} )) ))
    #echo "Used Percentage : $USEDPERC %"
    TOTMB=$(( $(( ${TOT#0} /1024 )) / 1024 ))
    USEDMB=$(( $(( ${USED#0} /1024 )) / 1024 ))
    FREEMB=$(( ${TOTMB#0} - $(( ${USEDMB#0} )) ))
    #echo "Used Percentage : $USEDPERC"

    if [ "$USEDPERC" -gt "80" ]; then
       SEND=1
       STATUS="Warning"
       echo "------------------------------------------------------------------" >> $LOG
       echo "$HOST Memory Status" >> $LOG
       echo "------------------------------------------------------------------" >> $LOG
       echo "Total Memory (GB)   : $TOTMB" >> $LOG
       echo "Used Memory (GB)    : $USEDMB" >> $LOG
       echo "Free Memory (GB)    : $FREEMB" >> $LOG
       echo "Used Percentage     : $USEDPERC %" >> $LOG
       echo "------------------------------------------------------------------" >> $LOG
       if [ "$USEDPERC" -gt "95" ]; then
          STATUS="Critical"
       fi
     else
       echo "------------------------------------------------------------------"
       echo "$HOST Memory Status"
       echo "------------------------------------------------------------------"

       echo "Total Memory (GB)   : $TOTMB"
       echo "Used Memory (GB)    : $USEDMB"
       echo "Free Memory (GB)    : $FREEMB"
       echo "Used Percentage     : $USEDPERC %"
       echo ""
     fi
  fi

  if [ "$FREEMB" -eq "0" ]; then
     SEND=1
     STATUS="Fatal"
     echo "------------------------------------------------------------------" >> $LOG
     echo " No free memory available in " `hostname` >>$LOG
     echo "------------------------------------------------------------------" >> $LOG
  fi
}

function netspeed(){
  interface=""
  received_bytes=""
  old_received_bytes=""
  transmitted_bytes=""
  old_transmitted_bytes=""

  if [ "$interface" == "" ]; then
    interface=$(ip -o -4 route show to default |awk '{ print $5; }')
  fi

  # This function parses /proc/net/dev file searching for a line containing $interface data.
  # Within that line, the first and ninth numbers after ':' are respectively the received and transmited bytes.
  get_bytes(){
    line=$(cat /proc/net/dev | grep $interface | cut -d ':' -f 2 | awk '{print "received_bytes="$1, "transmitted_bytes="$9}')
    eval $line
  }


  # Function which calculates the speed using actual and old byte number.
  # Speed is shown in KByte per second when greater or equal than 1 KByte per second.
  # This function should be called each second.
  get_velocity(){
    value=$1
    old_value=$2

    let vel=$value-$old_value
    let velKB=$vel/1000
    let velMB=$vel/1000000
    if [ $velMB != 0 ];
    then
      echo -n "$velMB MB/s";
    elif [ $velKB != 0 ];
    then
      echo -n "$velKB KB/s";
    else
      echo -n "$vel B/s";
    fi
  }

  # Gets initial values.
  get_bytes
  old_received_bytes=$received_bytes
  old_transmitted_bytes=$transmitted_bytes

  if [ "$2" != "" ] && [ "$2" == "now" ]; then
    sleep 1;

    # Get new transmitted and received byte number values.
    get_bytes

    # Calculates speeds.
    vel_recv=$(get_velocity $received_bytes $old_received_bytes)
    vel_trans=$(get_velocity $transmitted_bytes $old_transmitted_bytes)

    # Shows results in the console.
    #echo -en "$interface DOWN:$vel_recv\tUP:$vel_trans\r"
    #printf "%6s DOWN:%10s\tUP:%10s\r" "$interface" "$vel_recv" "$vel_trans"
    printf "%s UP:%10s\tDOWN:%10s\n" "$interface" "$vel_trans" "$vel_recv"

    # Update old values to perform new calculations.
    old_received_bytes=$received_bytes
    old_transmitted_bytes=$transmitted_bytes
  else
    # Shows a message and waits for one second.
    echo "Starting...";
    sleep 1;
    echo "";


    # Main loop. It will repeat forever.
    while true;
    do
      # Get new transmitted and received byte number values.
      get_bytes

      # Calculates speeds.
      vel_recv=$(get_velocity $received_bytes $old_received_bytes)
      vel_trans=$(get_velocity $transmitted_bytes $old_transmitted_bytes)

      # Shows results in the console.
      #echo -en "$interface DOWN:$vel_recv\tUP:$vel_trans\r"
      #printf "%6s DOWN:%10s\tUP:%10s\r" "$interface" "$vel_recv" "$vel_trans"
      printf "%6s UP:%10s\tDOWN:%10s\r" "$interface" "$vel_trans" "$vel_recv"

      # Update old values to perform new calculations.
      old_received_bytes=$received_bytes
      old_transmitted_bytes=$transmitted_bytes

      # Waits one second.
      sleep 1;

    done
  fi
}


$MOVE_TO_COL
echo "**********************************************"
$MOVE_TO_COL
echo -n "*            "
$SETCOLOR_FAILURE
echo -n "SERVER BACKUP OR RESTORE"
$SETCOLOR_NORMAL
echo -n "        *"
echo

$MOVE_TO_COL
echo "**********************************************"
$MOVE_TO_COL

echo ""
echo ""
$MOVE_TO_COL
echo "1) BACKUP SERVER"
$MOVE_TO_COL
echo "2) RESTORE SERVER"
$MOVE_TO_COL
echo "3) WAN IP"
$MOVE_TO_COL
echo "4) WAN SPEED TEST"
$MOVE_TO_COL
echo "5) RAM USED"
$MOVE_TO_COL
echo "6) ETHERNET TRANSFER SPEED"
$MOVE_TO_COL
echo "7) SERVER UPTIME"
$MOVE_TO_COL
echo "8) EXIT"
echo ""
$MOVE_TO_COL
echo -n "Please Select [1] or [2] or [3]  or [4] or [5] or [6] or [7] or [8]"
$SETCOLOR_SUCCESS
echo -n " [Default: 1] "
$SETCOLOR_NORMAL
read -p ": " choice
echo
$SETCOLOR_NORMAL

if test "$choice" = "1"
then
  cd /
  mkdir -p /data/warehouse
  NOW="$(date +"%Y%m%d")"
  FILE="/data/warehouse/backup.$NOW.tar.bz2"
  tar cvpjf $FILE --exclude=/proc --exclude=/lost+found --exclude=/backup.tar.bz2 --exclude=/mnt --exclude=/sys --exclude=/boot --exclude=/dev --exclude=/etc/fstab --exclude=/etc/sysconfig/network-scripts --exclude=/data --exclude=/nfs /

  echo ""
  echo ""
  $MOVE_TO_COL
  $SETCOLOR_SUCCESS

  echo ""
  echo ""
  echo "Backup has done."
fi

if test "$choice" = "2"
then
  cp /etc/fstab /tmp
  cd /
  tar xvpfj backup.tar.bz2 -C /
  mv /tmp/fstab /etc/

  echo ""
  echo ""
  echo "Restoration has done."
fi

if test "$choice" = "3"
then
  $MOVE_TO_COL
  curl ipinfo.io
  echo ""
fi

if test "$choice" = "4"
then
  $MOVE_TO_COL
  speedtest-cli
  echo ""
fi

if test "$choice" = "5"
then
  mem_used
fi

if test "$choice" = "6"
then
  netspeed
fi

if test "$choice" = "7"
then
  echo ""
  echo ""
  $MOVE_TO_COL
  time=$(date -d @$(( $(date +%s) - $(cut -f1 -d. /proc/uptime) )))
  echo "Server up time : $time"
  echo ""
fi


if test "$choice" = "8"
then
  exit
fi

