###
 # @description       : 
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 03/04/2020 11:31:50
 # @last modified     : 03/04/2020 14:35:51
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###
#!/bin/bash

# This shell script shows the network speed, both received and transmitted.

# Usage: net_speed.sh interface
#   e.g: net_speed.sh eth0


# Global variables
interface=$1
received_bytes=""
old_received_bytes=""
transmitted_bytes=""
old_transmitted_bytes=""

if [ "$interface" == "" ]
then
    interface=$(ip -o -4 route show to default |awk '{ print $5; }')
    #interface=$(nmcli device status | grep " connected" | awk '{print $1}')
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

