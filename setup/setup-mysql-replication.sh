#!/bin/bash

# -----------------------------------------------------------------------------
# MySQL Master-Master Replication Setup Script
# 
# This script automates the setup of MySQL master-master replication between
# two or more servers. It includes functionalities to:
# - Check for root permissions
# - Read and validate input parameters
# - Detect local IP if not provided
# - Configure MySQL settings for replication
# - Create replication users
# - Configure firewall rules
# - Provide monitoring scripts for replication status
#
# Usage:
#   ./setup-mysql-replication.sh [options]
#
# Options:
#   --remote-ip REMOTE_IP               IP address of the remote server(s)
#   --local-ip LOCAL_IP                 IP address of the local server
#   --server-id SERVER_ID               Unique server ID
#   --replica-user REPLICA_USER         Replication user name (default: replica)
#   --replica-password REPLICA_PASSWORD Replication user password (default: password)
#   --trusted-network TRUSTED_NETWORK   Trusted network range
#   --mysql-root-password MYSQL_ROOT_PASSWORD MySQL root password
#   --remote-log-file REMOTE_LOG_FILE   Remote log file for replication (optional)
#   --remote-log-pos REMOTE_LOG_POS     Remote log position for replication (optional)
#   --initialize                        Initialize the replication setup
#   --update                            Update the replication setup
#   --force                             Force the operation
#   --help                              Show this help message
#
# Examples:
#   Initialize replication on server A:
#     sudo ./setup_mysql_replication.sh --remote-ip 10.1.1.122 --server-id 1 --mysql-root-password yourpassword --initialize
#
#   Set up replication on server B:
#     sudo ./setup_mysql_replication.sh --remote-ip 10.1.1.210 --server-id 2 --mysql-root-password yourpassword --remote-log-file mysql-bin.000001 --remote-log-pos 1234
#
#   Update replication settings:
#     sudo ./setup_mysql_replication.sh --remote-ip 10.1.1.122 --server-id 1 --mysql-root-password yourpassword --remote-log-file mysql-bin.000002 --remote-log-pos 5678 --update
#
# -----------------------------------------------------------------------------

# Check if the script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "\e[31mThis script must be run as root\e[0m" 
       exit 1
    fi
}

# Initialize default variables
initialize_variables() {
    MYSQL_ROOT_PASSWORD=""
    REMOTE_IPS=()
    LOCAL_IP=""
    SERVER_ID=""
    REPLICA_USER="replica"
    REPLICA_PASSWORD="password"
    TRUSTED_NETWORK=""
    REMOTE_LOG_FILE=""
    REMOTE_LOG_POS=""
    INITIALIZE=false
    UPDATE=false
    FORCE=false
}

# Display help message
show_help() {
    echo -e "\e[34mUsage:\e[0m $0 [options]"
    echo -e "\e[34mOptions:\e[0m"
    echo -e "  \e[32m--remote-ip\e[0m             \e[37mREMOTE_IP\e[0m                IP address of the remote server(s)"
    echo -e "  \e[32m--local-ip\e[0m              \e[37mLOCAL_IP\e[0m                 IP address of the local server"
    echo -e "  \e[32m--server-id\e[0m             \e[37mSERVER_ID\e[0m                Unique server ID"
    echo -e "  \e[32m--replica-user\e[0m          \e[37mREPLICA_USER\e[0m             Replication user name (default: replica)"
    echo -e "  \e[32m--replica-password\e[0m      \e[37mREPLICA_PASSWORD\e[0m         Replication user password (default: password)"
    echo -e "  \e[32m--trusted-network\e[0m       \e[37mTRUSTED_NETWORK\e[0m          Trusted network range"
    echo -e "  \e[32m--mysql-root-password\e[0m   \e[37mMYSQL_ROOT_PASSWORD\e[0m      MySQL root password"
    echo -e "  \e[32m--remote-log-file\e[0m       \e[37mREMOTE_LOG_FILE\e[0m          Remote log file for replication (optional)"
    echo -e "  \e[32m--remote-log-pos\e[0m        \e[37mREMOTE_LOG_POS\e[0m           Remote log position for replication (optional)"
    echo -e "  \e[32m--initialize\e[0m                                     Initialize the replication setup"
    echo -e "  \e[32m--update\e[0m                                         Update the replication setup"
    echo -e "  \e[32m--force\e[0m                                          Force the operation"
    echo -e "  \e[32m--help\e[0m                                           Show this help message"
    echo
    echo -e "\e[34mExamples:\e[0m"
    echo -e "  \e[37mInitialize replication on server A:\e[0m"
    echo -e "    \e[32msudo $0 --remote-ip 10.1.1.122 --server-id 1 --mysql-root-password yourpassword --initialize\e[0m"
    echo
    echo -e "  \e[37mSet up replication on server B:\e[0m"
    echo -e "    \e[32msudo $0 --remote-ip 10.1.1.210 --server-id 2 --mysql-root-password yourpassword --remote-log-file mysql-bin.000001 --remote-log-pos 1234\e[0m"
    echo
    echo -e "  \e[37mUpdate replication settings:\e[0m"
    echo -e "    \e[32msudo $0 --remote-ip 10.1.1.122 --server-id 1 --mysql-root-password yourpassword --remote-log-file mysql-bin.000002 --remote-log-pos 5678 --update\e[0m"
    echo
}

# Read and parse input parameters
read_parameters() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --remote-ip|--slave-ip) REMOTE_IPS+=("$2"); shift ;;
            --local-ip) LOCAL_IP="$2"; shift ;;
            --server-id) SERVER_ID="$2"; shift ;;
            --replica-user) REPLICA_USER="$2"; shift ;;
            --replica-password) REPLICA_PASSWORD="$2"; shift ;;
            --trusted-network) TRUSTED_NETWORK="$2"; shift ;;
            --mysql-root-password) MYSQL_ROOT_PASSWORD="$2"; shift ;;
            --remote-log-file) REMOTE_LOG_FILE="$2"; shift ;;
            --remote-log-pos) REMOTE_LOG_POS="$2"; shift ;;
            --initialize) INITIALIZE=true ;;
            --update) UPDATE=true ;;
            --force) FORCE=true ;;
            --help) show_help; exit 0 ;;
            *) echo -e "\e[31mUnknown parameter passed: $1\e[0m"; show_help; exit 1 ;;
        esac
        shift
    done
}

# Check for required parameters
check_required_parameters() {
    if [[ ${#REMOTE_IPS[@]} -eq 0 || -z "$SERVER_ID" ]]; then
        echo -e "\e[31mError: Missing required parameters --remote-ip and/or --server-id\e[0m"
        show_help
        exit 1
    fi
}

# Automatically detect local IP if not provided
detect_local_ip() {
    if [[ -z "$LOCAL_IP" ]]; then
        IP_LIST=($(hostname -I))
        if [[ ${#IP_LIST[@]} -gt 1 ]]; then
            echo -e "\e[34mMultiple IP addresses detected. Please select one:\e[0m"
            select ip in "${IP_LIST[@]}"; do
                LOCAL_IP=$ip
                break
            done
        else
            LOCAL_IP=${IP_LIST[0]}
        fi

        if [[ -z "$LOCAL_IP" ]]; then
            echo -e "\e[31mError: Unable to detect local IP address. Please provide --local-ip parameter.\e[0m"
            exit 1
        fi
    fi
}

# Set auto increment values based on server ID and number of remote IPs
set_auto_increment_values() {
    AUTO_INCREMENT_INCREMENT=$(( ${#REMOTE_IPS[@]} + 1 ))
    AUTO_INCREMENT_OFFSET=$SERVER_ID
}

# Set trusted network if not provided
set_trusted_network() {
    if [[ -z "$TRUSTED_NETWORK" ]]; then
        for IP in "${REMOTE_IPS[@]}"; do
            TRUSTED_NETWORK+=" $IP/32"
        done
    fi
}

# Install MySQL if not already installed
install_mysql() {
    if ! command -v mysql &> /dev/null; then
        echo -e "\e[34mInstalling MySQL...\e[0m"
        yum install mysql-server -y
        systemctl start mysqld
        systemctl enable mysqld
    else
        echo -e "\e[34mMySQL is already installed\e[0m"
    fi
}

# Initialize MySQL and set root password if provided
initialize_mysql() {
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
    fi
}

# Configure firewall rules to allow MySQL replication
configure_firewall() {
    for IP in "${REMOTE_IPS[@]}"; do
        if ! firewall-cmd --list-sources --zone=trusted | grep -q "$IP"; then
            echo -e "\e[34mConfiguring firewall to trust network $IP...\e[0m"
            firewall-cmd --zone=trusted --add-source=${IP}/32 --permanent
            firewall-cmd --reload
        fi
    done

    if ! firewall-cmd --list-ports --zone=trusted | grep -q "3306/tcp"; then
        echo -e "\e[34mAdding MySQL port to firewall...\e[0m"
        firewall-cmd --zone=trusted --add-port=3306/tcp --permanent
        firewall-cmd --reload
    fi
}

# Determine the location of the MySQL configuration file
determine_mysql_config_location() {
    MY_CNF="/etc/my.cnf"
    if grep -q '!includedir /etc/my.cnf.d' $MY_CNF; then
        MY_CNF="/etc/my.cnf.d/mysql-server.cnf"
    fi
}

# Configure MySQL settings, avoiding duplicate entries
configure_mysql() {
    echo -e "\e[34mConfiguring MySQL...\e[0m"
    RESTART_REQUIRED=false
    if [[ -f $MY_CNF ]]; then
        if ! grep -q "server-id=$SERVER_ID" $MY_CNF; then
            if grep -q '\[mysqld\]' $MY_CNF; then
                echo -e "\e[34mAppending to existing [mysqld] section...\e[0m"
                sed -i "/\[mysqld\]/a server-id=$SERVER_ID\nlog_bin=mysql-bin\nauto_increment_increment=$AUTO_INCREMENT_INCREMENT\nauto_increment_offset=$AUTO_INCREMENT_OFFSET\nbind-address=$LOCAL_IP" $MY_CNF
            else
                echo -e "\e[34mCreating new [mysqld] section...\e[0m"
                echo -e "[mysqld]\nserver-id=$SERVER_ID\nlog_bin=mysql-bin\nauto_increment_increment=$AUTO_INCREMENT_INCREMENT\nauto_increment_offset=$AUTO_INCREMENT_OFFSET\nbind-address=$LOCAL_IP" >> $MY_CNF
            fi
            RESTART_REQUIRED=true
        else
            echo -e "\e[34mMySQL configuration already exists. Skipping...\e[0m"
        fi
    else
        echo -e "\e[34mCreating new MySQL configuration file...\e[0m"
        echo -e "[mysqld]\nserver-id=$SERVER_ID\nlog_bin=mysql-bin\nauto_increment_increment=$AUTO_INCREMENT_INCREMENT\nauto_increment_offset=$AUTO_INCREMENT_OFFSET\nbind-address=$LOCAL_IP" > $MY_CNF
        RESTART_REQUIRED=true
    fi

    # Restart MySQL to apply changes (only if configuration has changed)
    if $RESTART_REQUIRED; then
        systemctl restart mysqld
    fi
}

# Create replication user and configure mysql_native_password plugin
create_replication_user() {
    if ! $UPDATE; then
        echo -e "\e[34mCreating replication user...\e[0m"
        for IP in "${REMOTE_IPS[@]}"; do
            if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
                mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
DROP USER IF EXISTS '$REPLICA_USER'@'$IP';
CREATE USER '$REPLICA_USER'@'$IP' IDENTIFIED WITH mysql_native_password BY '$REPLICA_PASSWORD';
GRANT REPLICATION SLAVE ON *.* TO '$REPLICA_USER'@'$IP';
FLUSH PRIVILEGES;
EOF
            else
                mysql -u root <<EOF
DROP USER IF EXISTS '$REPLICA_USER'@'$IP';
CREATE USER '$REPLICA_USER'@'$IP' IDENTIFIED WITH mysql_native_password BY '$REPLICA_PASSWORD';
GRANT REPLICATION SLAVE ON *.* TO '$REPLICA_USER'@'$IP';
FLUSH PRIVILEGES;
EOF
            fi
        done
    fi
}

# Get the local master status for replication
get_local_master_status() {
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        LOCAL_MASTER_STATUS=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW MASTER STATUS\G")
    else
        LOCAL_MASTER_STATUS=$(mysql -u root -e "SHOW MASTER STATUS\G")
    fi
    LOCAL_LOG_FILE=$(echo "$LOCAL_MASTER_STATUS" | grep 'File:' | awk '{print $2}')
    LOCAL_LOG_POS=$(echo "$LOCAL_MASTER_STATUS" | grep 'Position:' | awk '{print $2}')

    # Display local master log file and position
    echo -e "\e[34mLocal Master log file:\e[0m $LOCAL_LOG_FILE"
    echo -e "\e[34mLocal Master log position:\e[0m $LOCAL_LOG_POS"
}

# Configure replication for the slave server
configure_replication() {
    if [[ -n "$REMOTE_LOG_FILE" && -n "$REMOTE_LOG_POS" ]]; then
        LOG_FILE_AND_POS=", MASTER_LOG_FILE='$REMOTE_LOG_FILE', MASTER_LOG_POS=$REMOTE_LOG_POS"
    else
        LOG_FILE_AND_POS=""
    fi

    echo -e "\e[34mConfiguring replication...\e[0m"
    for IP in "${REMOTE_IPS[@]}"; do
        if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
STOP SLAVE;
RESET SLAVE;
CHANGE MASTER TO MASTER_HOST='$IP', MASTER_USER='$REPLICA_USER', MASTER_PASSWORD='$REPLICA_PASSWORD' $LOG_FILE_AND_POS;
START SLAVE;
EOF
        else
            mysql -u root <<EOF
STOP SLAVE;
RESET SLAVE;
CHANGE MASTER TO MASTER_HOST='$IP', MASTER_USER='$REPLICA_USER', MASTER_PASSWORD='$REPLICA_PASSWORD' $LOG_FILE_AND_POS;
START SLAVE;
EOF
        fi
    done
}

# Check the status of the slave server
check_slave_status() {
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        SLAVE_STATUS=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW SLAVE STATUS\G")
    else
        SLAVE_STATUS=$(mysql -u root -e "SHOW SLAVE STATUS\G")
    fi
    echo "$SLAVE_STATUS"
}

# Set up the monitoring script for replication status
setup_monitoring_script() {
    if ! $UPDATE; then
        echo -e "\e[34mSetting up monitoring script...\e[0m"
        MONITOR_SCRIPT="/usr/local/bin/check_master.sh"
        echo "#!/bin/bash

for IP in ${REMOTE_IPS[@]}; do
    if ping -c 1 \$IP &> /dev/null; then
        echo \"Master server \$IP is reachable, starting slave...\"
        if [[ -n \"$MYSQL_ROOT_PASSWORD\" ]]; then
            mysql -u root -p'$MYSQL_ROOT_PASSWORD' -e \"START SLAVE;\"
        else
            mysql -u root -e \"START SLAVE;\"
        fi
    else
        echo \"Master server \$IP is not reachable, stopping slave...\"
        if [[ -n \"$MYSQL_ROOT_PASSWORD\" ]]; then
            mysql -u root -p'$MYSQL_ROOT_PASSWORD' -e \"STOP SLAVE;\"
        else
            mysql -u root -e \"STOP SLAVE;\"
        fi
    fi
done" > $MONITOR_SCRIPT
        chmod +x $MONITOR_SCRIPT

        # Set up cron job to run the monitoring script
        (crontab -l 2>/dev/null; echo "* * * * * $MONITOR_SCRIPT") | crontab -
    fi
}

# Main function to orchestrate the script workflow
main() {
    check_root
    initialize_variables
    read_parameters "$@"
    check_required_parameters
    detect_local_ip
    set_auto_increment_values
    set_trusted_network
    install_mysql
    initialize_mysql
    configure_firewall
    determine_mysql_config_location
    configure_mysql
    create_replication_user
    get_local_master_status
    configure_replication
    check_slave_status
    setup_monitoring_script

    echo
    echo -e "\e[32mMySQL Master-Master Replication setup complete on server $SERVER_ID.\e[0m"

    if ! $INITIALIZE; then
        get_local_master_status
    fi
}

main "$@"
