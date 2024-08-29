#!/bin/bash

###############################################################################
# Galera MySQL Installation Script for CentOS 8, 9 and Oracle Linux 8, 9
#
# This script automates the installation and configuration of MySQL with Galera 
# for CentOS 8, 9 and Oracle Linux 8, 9. Galera provides a synchronous multi-master
# cluster for MySQL, which allows for high availability and redundancy.
# Due to Galera's lack of support for CentOS 7 and below, this script provides 
# an alternative installation method in a supported environment.
#
# Occasionally, when new versions of MySQL or Galera are released, the URLs for 
# older versions may be removed from the official repositories. If you encounter 
# download failures during script execution, visit the Galera Cluster Downloads page
# at https://galeracluster.com/downloads/ to download the latest version. You will
# need to update the URLs in this script accordingly.
#
# Usage:
#   Initialize a new node:
#     ./script_name.sh --initialize [--mysql-root-password YourPassword] [--cluster-nodes 10.1.1.122,10.1.1.123]
#
#   Add a node to an existing cluster:
#     ./script_name.sh --add-node --mysql-root-password YourPassword --cluster-nodes 10.1.1.122,10.1.1.123
#
# For more information, run:
#   ./script_name.sh --help
#
###############################################################################

# Global Variables
MYSQL_WSREP_URL="https://releases.galeracluster.com/mysql-wsrep-8.0/binary/mysql-wsrep-8.0.39-26.20-linux-x86_64.tar.gz"
GALERA_URL="https://releases.galeracluster.com/galera-4/binary/galera-4-26.4.20-Linux-x86_64.tar.gz"
CLUSTER_NAME="my_galera_cluster"
DEFAULT_IP=$(hostname -I | awk '{print $1}')  # Default to the first IP address
NODE_IP="$DEFAULT_IP"
MYSQL_ROOT_PASSWORD=""
REPLICATION_MODE="master-master"
CLUSTER_NODES=()
LOG_FILE="/var/log/mysql_galera_install.log"
BACKUP_DIR="/var/backups/mysql"

# Function: log
# Logs messages to a log file with a timestamp.
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function: show_help
# Displays help information for the script, including usage examples and options.
show_help() {
    echo -e "\e[1;34mUsage:\e[0m"
    echo -e "  $0 [options]"
    echo ""
    echo -e "\e[1;34mOptions for Initialization:\e[0m"
    echo -e "  \e[1;32m--initialize\e[0m                      Initialize MySQL and Galera on this node. Can optionally use:"
    echo -e "    \e[1;32m--mysql-root-password <pass>\e[0m   Set the MySQL root password."
    echo -e "    \e[1;32m--cluster-nodes <IP1,IP2,...>\e[0m  Comma-separated list of all cluster node IPs (if any)."
    echo ""
    echo -e "\e[1;34mOptions for Adding Nodes to an Existing Cluster:\e[0m"
    echo -e "  \e[1;32m--add-node\e[0m                       Add this node to an existing Galera cluster. Must be used with the following options:"
    echo -e "    \e[1;32m--mysql-root-password <pass>\e[0m   Set the MySQL root password."
    echo -e "    \e[1;32m--cluster-nodes <IP1,IP2,...>\e[0m  Comma-separated list of all cluster node IPs."
    echo ""
    echo -e "\e[1;34mGeneral Options:\e[0m"
    echo -e "  \e[1;32m--node-ip <IP>\e[0m                   Set the IP address of the current node (if different from default)."
    echo -e "  \e[1;32m--replication-mode <mode>\e[0m        Set replication mode: master-master or master-slave."
    echo -e "  \e[1;32m--force\e[0m                          Force the operation (use with caution)."
    echo -e "  \e[1;32m--help\e[0m                           Show this help message."
    echo ""
    echo -e "\e[1;34mExamples:\e[0m"
    echo -e "  \e[1;33mInitialize a new node:\e[0m"
    echo -e "    $0 --initialize"
    echo -e "    $0 --initialize --mysql-root-password YourPassword --cluster-nodes 10.1.1.122,10.1.1.123"
    echo ""
    echo -e "  \e[1;33mAdd a node to an existing cluster:\e[0m"
    echo -e "    $0 --add-node --mysql-root-password YourPassword --cluster-nodes 10.1.1.122,10.1.1.123"
    echo ""
    echo -e "\e[1;34mNote:\e[0m"
    echo -e "  \e[1;31m--initialize\e[0m and \e[1;31m--add-node\e[0m cannot be used together."
    echo -e "  Ensure the cluster nodes are correctly listed in \e[1;32m--cluster-nodes\e[0m when adding a node."
}

# Function: read_parameters
# Parses command-line parameters and sets global variables accordingly.
read_parameters() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --node-ip) NODE_IP="$2"; shift ;;
            --cluster-name) CLUSTER_NAME="$2"; shift ;;
            --cluster-nodes) IFS=',' read -r -a CLUSTER_NODES <<< "$2"; shift ;;
            --mysql-root-password) MYSQL_ROOT_PASSWORD="$2"; shift ;;
            --replication-mode) REPLICATION_MODE="$2"; shift ;;
            --initialize) INITIALIZE=true ;;
            --add-node) ADD_NODE=true ;;
            --force) FORCE=true ;;
            --help) show_help; exit 0 ;;
            *)
                echo -e "\e[31mUnknown parameter passed: $1\e[0m"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    # Ensure that --initialize and --add-node are not used together
    if [ "${INITIALIZE}" == true ] && [ "${ADD_NODE}" == true ]; then
        echo -e "\e[31mCannot use --initialize and --add-node together\e[0m"
        show_help
        exit 1
    fi

    # If initializing and no root password is provided, prompt for one
    if [ "${INITIALIZE}" == true ] && [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        read -sp "Enter MySQL root password (leave empty to skip setting root password): " MYSQL_ROOT_PASSWORD
        echo ""
    fi

    # Ensure required parameters are provided when adding a node
    # if [ "${ADD_NODE}" == true ]; then
    #     if [ -z "${CLUSTER_NODES}" ] || [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    #         echo -e "\e[31m--cluster-nodes and --mysql-root-password are required when using --add-node\e[0m"
    #         show_help
    #         exit 1
    #     fi
    # fi
}

# Function: check_root
# Ensures the script is run as the root user.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script must be run as root."
        exit 1
    fi
}

# Function: install_dependencies
# Installs required dependencies for MySQL and Galera.
install_dependencies() {
    log "Updating system and installing dependencies..."
    sudo yum install -y libaio ncurses-compat-libs rsync lsof wget || {
        log "Failed to install dependencies."
        exit 1
    }
}

# Function: configure_firewall
# Configures firewall rules for MySQL and Galera ports and adds node IPs to trusted zone.
configure_firewall() {
    log "Configuring firewall..."
    sudo firewall-cmd --zone=trusted --permanent --add-port=4567/tcp
    sudo firewall-cmd --zone=trusted --permanent --add-port=4568/tcp
    sudo firewall-cmd --zone=trusted --permanent --add-port=4444/tcp
    sudo firewall-cmd --zone=trusted --permanent --add-port=3306/tcp

    # Debug output to check CLUSTER_NODES content
    echo "CLUSTER_NODES contains: ${CLUSTER_NODES[@]}"

    # Add node IPs to the trusted zone
    for node_ip in "${CLUSTER_NODES[@]}"; do
        log "Adding node IP $node_ip to trusted zone..."
        sudo firewall-cmd --zone=trusted --permanent --add-source="$node_ip" || {
            log "Failed to add node IP $node_ip to firewall trusted zone."
        }
    done

    sudo firewall-cmd --reload || {
        log "Failed to reload firewall."
        exit 1
    }
}

# Function: add_firewall_for_node
# Updates firewall rules to add new node IPs to trusted zone for add node operation.
add_firewall_for_node() {
    log "Updating firewall for new node..."
    
    # Only add new node IPs to the trusted zone
    for node_ip in "${CLUSTER_NODES[@]}"; do
        log "Adding node IP $node_ip to trusted zone..."
        sudo firewall-cmd --zone=trusted --permanent --add-source="$node_ip" || {
            log "Failed to add node IP $node_ip to firewall trusted zone."
        }
    done

    sudo firewall-cmd --reload || {
        log "Failed to reload firewall."
        exit 1
    }
}


# Function: check_and_backup_databases
# Checks for existing MySQL databases (other than default ones) and prompts for backup.
check_and_backup_databases() {
    # Construct the MySQL command based on whether a password is provided
    if [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
        mysql_command="mysql -u root -p\"${MYSQL_ROOT_PASSWORD}\""
    else
        mysql_command="mysql -u root"
    fi

    # Check for non-default databases
    existing_dbs=$(${mysql_command} -e "SHOW DATABASES;" | grep -Ev "^(Database|information_schema|performance_schema|mysql|sys)$")
    
    if [ -n "$existing_dbs" ]; then
        echo -e "\e[1;33mNon-default databases detected:\e[0m"
        echo "$existing_dbs"
        read -p "Would you like to backup these databases before uninstalling MySQL? (y/n): " backup_choice
        if [[ "$backup_choice" == "y" || "$backup_choice" == "Y" ]]; then
            log "Backing up databases..."
            sudo mkdir -p "$BACKUP_DIR"
            for db in $existing_dbs; do
                if [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
                    mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" "$db" > "$BACKUP_DIR/${db}_backup.sql"
                else
                    mysqldump -u root "$db" > "$BACKUP_DIR/${db}_backup.sql"
                fi
                log "Database $db backed up to $BACKUP_DIR/${db}_backup.sql"
            done
        fi
    else
        log "No non-default databases found."
    fi
}

# Function: remove_existing_mysql
# Removes any existing MySQL installation to ensure a clean setup.
remove_existing_mysql() {
    if command -v mysql &> /dev/null; then
        check_and_backup_databases
    fi

    log "Removing existing MySQL installation..."
    sudo systemctl stop mysqld
    sudo systemctl disable mysqld
    sudo yum remove -y mysql mysql-server
    sudo rm -rf /var/lib/mysql /var/log/mysql /etc/my.cnf
}

# Function: create_mysql_user
# Creates the MySQL user if it does not already exist.
create_mysql_user() {
    if id -u mysql &>/dev/null; then
        log "MySQL user exists."
    else
        sudo useradd -r -s /bin/false mysql
        log "MySQL user created."
    fi
}

# Function: configure_mysql_directory
# Configures permissions and ownership for MySQL directories.
configure_mysql_directory() {
    log "Configuring MySQL data directory permissions..."
    sudo mkdir -p /var/lib/mysql /var/run/mysqld
    sudo chown mysql:mysql /var/lib/mysql /var/run/mysqld
    sudo chmod 755 /var/lib/mysql /var/run/mysqld

    # Ensure MySQL log directory exists
    sudo mkdir -p /var/log/mysqld
    sudo touch /var/log/mysqld/mysqld.log
    sudo chown mysql:mysql /var/log/mysqld/mysqld.log
    sudo chmod 644 /var/log/mysqld/mysqld.log
}

# Function: check_existing_files
# Checks for existing mysql-wsrep and galera tar.gz files and prompts the user to use them or download new ones.
check_existing_files() {
    # Only check for files if initializing
    if [ "${INITIALIZE}" == true ]; then
        local mysql_wsrep_file
        local galera_file

        # Check for existing mysql-wsrep tar.gz files
        mysql_wsrep_file=$(ls | grep -E "^mysql-wsrep.*\.tar\.gz$" | head -n 1)
        galera_file=$(ls | grep -E "^galera.*\.tar\.gz$" | head -n 1)

        if [[ -n "$mysql_wsrep_file" ]]; then
            echo -e "\e[1;33mDetected local mysql-wsrep file: $mysql_wsrep_file\e[0m"
            read -p "Do you want to use this local file instead of downloading? (y/n): " use_local_mysql_wsrep
            if [[ "$use_local_mysql_wsrep" == "y" || "$use_local_mysql_wsrep" == "Y" ]]; then
                MYSQL_WSREP_FILE="$mysql_wsrep_file"
                log "Using local mysql-wsrep file: $MYSQL_WSREP_FILE"
            else
                MYSQL_WSREP_FILE=""
            fi
        fi

        if [[ -n "$galera_file" ]]; then
            echo -e "\e[1;33mDetected local galera file: $galera_file\e[0m"
            read -p "Do you want to use this local file instead of downloading? (y/n): " use_local_galera
            if [[ "$use_local_galera" == "y" || "$use_local_galera" == "Y" ]]; then
                GALERA_FILE="$galera_file"
                log "Using local galera file: $GALERA_FILE"
            else
                GALERA_FILE=""
            fi
        fi
    fi
}

# Function: download_and_extract
# Downloads and extracts MySQL and Galera binaries or uses local versions if specified.
download_and_extract() {
    # Only download and extract if initializing
    if [ "${INITIALIZE}" == true ]; then
        log "Downloading and extracting MySQL and Galera..."

        # Ensure target directories exist
        sudo mkdir -p /usr/local/mysql-wsrep /usr/local/galera

        # Check if local files are set and use them if available
        if [[ -n "$MYSQL_WSREP_FILE" ]]; then
            log "Using local mysql-wsrep file: $MYSQL_WSREP_FILE"
            sudo tar -xzf "$MYSQL_WSREP_FILE" -C /usr/local/mysql-wsrep --strip-components=1
        else
            wget ${MYSQL_WSREP_URL} -O mysql-wsrep.tar.gz
            if [ $? -ne 0 ]; then
                log "Failed to download MySQL WSREP. Please visit https://galeracluster.com/downloads/ to download the latest version and update the script URL."
                exit 1
            fi
            sudo tar -xzf mysql-wsrep.tar.gz -C /usr/local/mysql-wsrep --strip-components=1
        fi

        if [[ -n "$GALERA_FILE" ]]; then
            log "Using local galera file: $GALERA_FILE"
            sudo tar -xzf "$GALERA_FILE" -C /usr/local/galera --strip-components=1
        else
            wget ${GALERA_URL} -O galera.tar.gz
            if [ $? -ne 0 ]; then
                log "Failed to download Galera. Please visit https://galeracluster.com/downloads/ to download the latest version and update the script URL."
                exit 1
            fi
            sudo tar -xzf galera.tar.gz -C /usr/local/galera --strip-components=1
        fi
    fi
}


# Function: configure_mysql
# Configures MySQL with dynamic settings based on server resources and additional recommended settings.
configure_mysql() {
    log "Configuring MySQL..."

    # Detect RAM size in MB
    RAM_SIZE_MB=$(free -m | awk '/^Mem:/{print $2}')
    
    # Determine buffer sizes based on RAM
    if [ "$RAM_SIZE_MB" -ge 8192 ]; then
        INNODB_BUFFER_POOL_SIZE="512M"
        KEY_BUFFER_SIZE="512M"
    elif [ "$RAM_SIZE_MB" -ge 4096 ]; then
        INNODB_BUFFER_POOL_SIZE="256M"
        KEY_BUFFER_SIZE="256M"
    else
        INNODB_BUFFER_POOL_SIZE="128M"
        KEY_BUFFER_SIZE="128M"
    fi

    cat <<EOF | sudo tee /etc/my.cnf
[client]
socket				= /var/lib/mysql/mysql.sock

[mysqld]
user				= mysql
basedir				= /usr/local/mysql-wsrep
datadir				= /var/lib/mysql
socket				= /var/lib/mysql/mysql.sock
log-error			= /var/log/mysqld/mysqld.log
pid-file			= /var/run/mysqld/mysqld.pid
tmpdir 				= /tmp

# MySQL settings
binlog_format			= row
default_storage_engine		= InnoDB
innodb_autoinc_lock_mode	= 2

# Additional MySQL settings
default-authentication-plugin 	= mysql_native_password
collation-server 		= utf8mb4_0900_ai_ci
init-connect 			= 'SET NAMES utf8mb4'
character-set-server 		= utf8mb4
skip-character-set-client-handshake = true

slow_query_log 			= 1
slow-query_log_file 		= /var/log/mysqld/mysql-slow.log
long_query_time 		= 3
max_connections 		= 5000
key_buffer_size 		= ${KEY_BUFFER_SIZE}
innodb_buffer_pool_size 	= ${INNODB_BUFFER_POOL_SIZE}
max_allowed_packet 		= 256M
innodb_log_file_size 		= 128M
innodb_thread_concurrency 	= 0
innodb_concurrency_tickets 	= 8
innodb_read_io_threads 		= 8
innodb_write_io_threads 	= 8
sql_mode 			= ""
symbolic-links 			= 0
skip_external_locking
innodb_file_per_table

EOF

    if [ -n "${CLUSTER_NODES[*]}" ]; then
        cat <<EOF | sudo tee -a /etc/my.cnf

# Galera settings
wsrep_on			= ON
wsrep_provider			= /usr/local/galera/lib/libgalera_smm.so
wsrep_cluster_address		= gcomm://$(IFS=,; echo "${CLUSTER_NODES[*]}")
wsrep_cluster_name		= "${CLUSTER_NAME}"
wsrep_node_address		= ${NODE_IP}
wsrep_node_name			= $(hostname)
wsrep_sst_method		= rsync

EOF
    fi

    # Ensure the MySQL slow query log file exists
    sudo touch /var/log/mysql-slow.log
    sudo chown mysql:mysql /var/log/mysql-slow.log
}

# Function: initialize_mysql
# Initializes MySQL data directory and updates environment variables.
initialize_mysql() {
    log "Initializing MySQL data directory..."

    # Add MySQL binary path to /etc/profile if not already present
    if ! grep -q "/usr/local/mysql-wsrep/bin" /etc/profile; then
        echo -e "\nexport PATH=\$PATH:/usr/local/mysql-wsrep/bin" >> /etc/profile
    fi

    # Export the path in the current shell session
    export PATH=$PATH:/usr/local/mysql-wsrep/bin

    # Initialize the MySQL data directory
    sudo /usr/local/mysql-wsrep/bin/mysqld --defaults-file=/etc/my.cnf --initialize-insecure --user=mysql

    # Check if initialization was successful
    if [ $? -ne 0 ]; then
        log "Failed to initialize MySQL data directory."
        exit 1
    fi

    log "MySQL data directory initialized successfully."
}

# Function: create_systemd_service
# Creates a systemd service file for MySQL.
create_systemd_service() {
    log "Creating MySQL systemd service file..."
    cat <<EOF | sudo tee /etc/systemd/system/mysqld.service
[Unit]
Description=MySQL 8.0 database server
After=network.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=/bin/mkdir -p /var/run/mysqld
ExecStartPre=/bin/chown mysql:mysql /var/run/mysqld
ExecStart=/usr/local/mysql-wsrep/bin/mysqld --defaults-file=/etc/my.cnf --daemonize --pid-file=/var/run/mysqld/mysqld.pid
ExecStop=/usr/local/mysql-wsrep/bin/mysqladmin shutdown
PIDFile=/var/run/mysqld/mysqld.pid
User=mysql
Group=mysql
Restart=on-failure
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF
}

# Function: start_mysql_service
# Starts the MySQL service using systemd.
start_mysql_service() {
    log "Starting MySQL service..."
    sudo systemctl start mysqld
    sleep 5  # Wait for the service to start
    if [ $? -ne 0 ]; then
        log "Failed to start MySQL service. Check logs for details."
        systemctl status mysqld.service
        exit 1
    fi
}

# Function: configure_mysql_root_password
# Configures the root password for MySQL.
configure_mysql_root_password() {
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        log "Configuring MySQL root user password..."
        if [ -f /var/log/mysqld/mysqld.log ]; then
            temp_password=$(sudo grep 'temporary password' /var/log/mysqld/mysqld.log | awk '{print $NF}')
            if [ -z "$temp_password" ]; then
                log "Temporary password not found in log file."
                exit 1
            fi
            mysqladmin -u root --password="${temp_password}" password "${MYSQL_ROOT_PASSWORD}" || {
                log "Failed to configure MySQL root password."
                exit 1
            }
        else
            log "MySQL log file not found. Service might not have started correctly."
            exit 1
        fi
    else
        log "Skipping root password configuration as no password provided."
    fi
}

# Function: add_node
# Adds the current node to an existing Galera cluster.
add_node() {
    log "Adding node to Galera cluster..."

    # Call firewall update function to ensure node IPs are added to trusted zone
    add_firewall_for_node

    # Check if Galera settings already exist in /etc/my.cnf
    if grep -qP "^\s*wsrep_on\s*=\s*ON" /etc/my.cnf; then
        log "Galera settings detected in /etc/my.cnf, updating configuration..."

        # Read existing wsrep_cluster_address from /etc/my.cnf
        existing_cluster_address=$(sudo grep -oP '^\s*wsrep_cluster_address\s*=\s*gcomm://.*' /etc/my.cnf | sed 's/^\s*wsrep_cluster_address\s*=\s*gcomm:\/\///')
        
        # Convert existing addresses into an array
        IFS=',' read -r -a existing_nodes <<< "$existing_cluster_address"
        
        # Combine existing nodes with new cluster nodes
        combined_nodes=("${existing_nodes[@]}" "${CLUSTER_NODES[@]}")
        
        # Remove duplicate nodes from the combined array
        combined_nodes=($(echo "${combined_nodes[@]}" | tr ' ' '\n' | sort -u | tr '\n' ','))

        # Remove trailing comma
        combined_nodes="${combined_nodes%,}"

        # Update the my.cnf file with new nodes
        sudo sed -i "s|\(wsrep_cluster_address\s*=\s*gcomm://\).*|\1${combined_nodes}|" /etc/my.cnf

    else
        log "No Galera settings found in /etc/my.cnf, adding new configuration..."

        # Call configure_mysql to add the new Galera configuration
        configure_mysql
    fi

    log "Restarting MySQL service to join the cluster..."
    sudo systemctl stop mysqld
    sudo systemctl start mysqld || {
        log "Failed to start MySQL service. Check logs for details."
        exit 1
    }
    log "Node added to Galera cluster."
}

# Main Function
main() {
    check_root
    read_parameters "$@"
    check_existing_files  # Added line to check for existing files

    log "Current PATH: $PATH"

    if [ "${INITIALIZE}" == true ]; then
        install_dependencies
        configure_firewall
        remove_existing_mysql
        create_mysql_user
        configure_mysql_directory
        download_and_extract  # Updated function call
        configure_mysql
        initialize_mysql
        create_systemd_service
        sudo systemctl daemon-reload
        sudo systemctl enable mysqld
        start_mysql_service
        configure_mysql_root_password
        log "MySQL and Galera initialization completed."
    elif [ "${ADD_NODE}" == true ]; then
        add_node
    else
        show_help
    fi
}

main "$@"
