#!/bin/bash

# GlusterFS Cluster Configuration Script
# This script automates the initialization, joining, rejoining, and linking of nodes in a GlusterFS cluster.
# It also handles dependency installation, firewall configuration, and volume management.
#
# Usage:
#   See the '--help' option for detailed usage instructions.

# Default settings
DEFAULT_VOLUME_NAME="myvolume"
DEFAULT_BRICK_PATH="/data/.glusterfs"
DEFAULT_MOUNT_POINT="/mnt/glusterfs"
GLUSTER_VERSION="11.1"

# Color codes for highlighting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

# Separator for output clarity
SEPARATOR="------------------------------------------------------------"

# Auto-detect local IP
function detect_ip() {
  IP_ADDR=$(hostname -I | awk '{print $1}')
  echo "$IP_ADDR"
}

# Function to display help
function show_help() {
  echo -e "${BLUE}Usage:${NC}"
  echo "  sh $0 [options]"
  echo ""

  echo -e "${BLUE}Options for Initialization:${NC}"
  echo -e "  ${GREEN}--initialize${NC}                         Initialize GlusterFS on this node."
  echo -e "    ${GREEN}--volume-name <name>${NC}                (Optional) Set a custom volume name (default is ${RED}\"$DEFAULT_VOLUME_NAME\"${NC})."
  echo -e "    ${GREEN}--brick-path <path>${NC}                 (Optional) Set a custom brick path (default is ${RED}\"$DEFAULT_BRICK_PATH\"${NC})."
  echo -e "    ${GREEN}--mount-point <path>${NC}                (Optional) Set a custom mount point (default is ${RED}\"$DEFAULT_MOUNT_POINT\"${NC})."
  echo -e "    ${GREEN}--cluster-nodes <IP1,IP2,...>${NC}       (Required) Comma-separated list of all cluster node IPs."
  echo ""

  echo -e "${BLUE}Options for Adding a Node to the GlusterFS Cluster:${NC}"
  echo -e "  ${GREEN}--add-node${NC}                            Add this node to an existing GlusterFS cluster from the master cluster."
  echo -e "    ${GREEN}--cluster-nodes <IP1,IP2,...>${NC}       (Optional) Comma-separated list of all cluster node IPs."
  echo ""

  echo -e "${BLUE}Options for Joining an Existing Cluster:${NC}"
  echo -e "  ${GREEN}--join${NC}                                Join this node to an existing GlusterFS cluster in the new server."
  echo -e "    ${GREEN}--master-node <IP>${NC}                  (Required) IP address of the master node to join."
  echo ""

  echo -e "${BLUE}Options for Rejoining a Cluster:${NC}"
  echo -e "  ${GREEN}--rejoin${NC}                              Rejoin this node to an existing GlusterFS cluster."
  echo -e "    ${GREEN}--cluster-nodes <IP1,IP2,...>${NC}       (Required) Comma-separated list of all cluster node IPs."
  echo ""

  echo -e "${BLUE}Options for Linking a Node to a Cluster:${NC}"
  echo -e "  ${GREEN}--link${NC}                                Link this node to the cluster and wait for the master node's confirmation."
  echo -e "    ${GREEN}--master-node <IP>${NC}                  (Required) IP address of the master node to link."
  echo ""

  echo -e "${BLUE}General Options:${NC}"
  echo -e "  ${GREEN}--node-ip <IP>${NC}                        Set the IP address of the current node (if different from the default)."
  echo -e "  ${GREEN}--help${NC}                                Show this help message."
  echo ""

  echo -e "${BLUE}Examples:${NC}"
  echo -e "  ${GREEN}Initialize a new node:${NC}"
  echo -e "    sh $0 ${GREEN}--initialize --cluster-nodes 10.1.1.210,10.1.1.122${NC}"
  echo ""

  echo -e "  ${GREEN}Add a node to an existing cluster:${NC}"
  echo -e "    sh $0 ${GREEN}--add-node --cluster-nodes 10.1.1.210,10.1.1.122${NC}"
  echo ""

  echo -e "  ${GREEN}Join a node to an existing cluster:${NC}"
  echo -e "    sh $0 ${GREEN}--join --master-node 10.1.1.210${NC}"
  echo ""

  echo -e "  ${GREEN}Rejoin a node to an existing cluster:${NC}"
  echo -e "    sh $0 ${GREEN}--rejoin --cluster-nodes 10.1.1.210,10.1.1.122${NC}"
  echo ""

  echo -e "  ${GREEN}Link a node to the cluster and wait for connection:${NC}"
  echo -e "    sh $0 ${GREEN}--link --master-node 10.1.1.210${NC}"
  echo ""

  echo -e "  ${GREEN}Reset GlusterFS configuration:${NC}"
  echo -e "    sh $0 ${GREEN}--reset${NC}"
  echo ""

  echo -e "${SEPARATOR}"
}

# Adding SEPARATOR for consistency in output
SEPARATOR="\n${BLUE}-------------------------------------------------------${NC}\n"


# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run this script as root.${NC}"
  exit
fi

# Parse arguments
INITIALIZE=0
ADD_NODE=0
JOIN_NODE=0
REJOIN=0
RESET=0
LINK=0
NODE_IP=""
CLUSTER_NODES=""
MASTER_NODE=""
VOLUME_NAME=$DEFAULT_VOLUME_NAME
BRICK_PATH=$DEFAULT_BRICK_PATH
MOUNT_POINT=$DEFAULT_MOUNT_POINT


# Filter out local IP from cluster-nodes
function filter_local_ip() {
  if [ -n "$CLUSTER_NODES" ]; then
    IFS=',' read -ra NODES <<< "$CLUSTER_NODES"
    NEW_NODES=()
    for PEER in "${NODES[@]}"; do
      if [ "$PEER" != "$NODE_IP" ]; then
        NEW_NODES+=("$PEER")
      fi
    done
    CLUSTER_NODES=$(IFS=','; echo "${NEW_NODES[*]}")
  fi
}

# Link node to cluster
function link_node_to_cluster() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Linking node to cluster and waiting for master node's confirmation...${NC}"
  echo -e "${SEPARATOR}"
  
  check_glusterfs_installed
  configure_firewall
  configure_glusterfs
  reset_gluster
  echo -e "${BLUE}Waiting for master node $MASTER_NODE to connect...${NC}"
  
  while ! gluster peer status | grep -q 'Peer in Cluster'; do
    echo -e "${BLUE}Waiting...${NC}"
    sleep 5
  done

  echo -e "${GREEN}Master node connected! Proceeding with mount and configuration...${NC}"
  auto_mount_volume
}

# Initialize GlusterFS
function initialize_glusterfs() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Initializing GlusterFS...${NC}"
  echo -e "${SEPARATOR}"

  install_dependencies
  configure_firewall

  # Check for local GlusterFS tarball
  local_tarball=$(ls glusterfs*.tar.gz 2>/dev/null | head -n 1)
  if [ -n "$local_tarball" ]; then
    echo -e "${GREEN}Local GlusterFS tarball detected: $local_tarball${NC}"
    read -p "Do you want to use the local tarball instead of downloading? (y/n): " use_local
    if [[ "$use_local" =~ ^[Yy]$ ]]; then
      compile_glusterfs "$local_tarball"
    else
      compile_glusterfs
    fi
  else
    compile_glusterfs
  fi

  configure_glusterfs
  create_brick_directory
  
  if [ -n "$CLUSTER_NODES" ]; then
    filter_local_ip
    echo -e "${RED}Please run the following command on other cluster nodes (e.g., on 10.1.1.122):${NC}"
    echo "$0 --link --master-node $NODE_IP"
    echo -e "${BLUE}After running the command on other nodes, press [Enter] to continue...${NC}"
    read -p "Press [Enter] to continue once all nodes are linked: "

    auto_join_cluster
  else
    create_local_volume
    auto_mount_volume
  fi
}

# Install dependencies
function install_dependencies() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Updating system and installing necessary dependencies...${NC}"
  echo -e "${SEPARATOR}"
  
  dnf groupinstall "Development Tools" -y
  dnf install -y autoconf automake bison flex libtool libaio-devel libxml2-devel readline-devel pkgconfig python3-devel openssl-devel userspace-rcu-devel libuuid-devel libibverbs-devel glib2-devel libacl-devel librdmacm-devel libtirpc-devel liburing-devel libmount-devel rpcgen gperftools gperftools-devel attr glusterfs glusterfs-client
}

# Configure firewall
function configure_firewall() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Configuring firewall to trusted zone...${NC}"
  echo -e "${SEPARATOR}"

  if command -v firewall-cmd &> /dev/null; then
    if ! firewall-cmd --list-ports --zone=trusted | grep -q '24007-24008/tcp'; then
      firewall-cmd --zone=trusted --add-port=24007-24008/tcp --permanent
    fi

    if ! firewall-cmd --list-ports --zone=trusted | grep -q '49152-49251/tcp'; then
      firewall-cmd --zone=trusted --add-port=49152-49251/tcp --permanent
    fi
    
    IFS=',' read -ra NODES <<< "$CLUSTER_NODES"
    for PEER in "${NODES[@]}"; do
      if ! firewall-cmd --list-sources --zone=trusted | grep -q "$PEER"; then
        firewall-cmd --zone=trusted --add-source=$PEER --permanent
      fi
    done
    
    firewall-cmd --reload
  else
    echo -e "${RED}Firewall command not found, skipping firewall configuration.${NC}"
  fi
}

# Compile and install GlusterFS
function compile_glusterfs() {
  local tarball="$1"

  if [ -n "$tarball" ]; then
    echo -e "${SEPARATOR}"
    echo -e "${BLUE}Using local GlusterFS source tarball: $tarball${NC}"
    echo -e "${SEPARATOR}"
  else
    echo -e "${SEPARATOR}"
    echo -e "${BLUE}Downloading the latest version of GlusterFS source code...${NC}"
    echo -e "${SEPARATOR}"
    
    wget https://download.gluster.org/pub/gluster/glusterfs/LATEST/glusterfs-$GLUSTER_VERSION.tar.gz
    tarball="glusterfs-$GLUSTER_VERSION.tar.gz"
  fi

  echo -e "${BLUE}Extracting source code and entering directory...${NC}"
  tar -zxvf "$tarball"
  cd "${tarball%.tar.gz}"

  echo -e "${BLUE}Configuring and compiling GlusterFS...${NC}"
  ./autogen.sh
  ./configure
  make
  make install

  echo -e "${GREEN}Updating environment variables...${NC}"
  export PATH=$PATH:/usr/local/sbin:/usr/local/bin
  echo 'export PATH=$PATH:/usr/local/sbin:/usr/local/bin' >> ~/.bashrc
  source ~/.bashrc
}

# Configure GlusterFS
function configure_glusterfs() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Starting and enabling GlusterFS service...${NC}"
  echo -e "${SEPARATOR}"
  
  systemctl start glusterd
  systemctl enable glusterd
}

# Create brick directory
function create_brick_directory() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Creating brick directory: $BRICK_PATH${NC}"
  echo -e "${SEPARATOR}"
  
  mkdir -p $BRICK_PATH
}

# Create GlusterFS volume
function create_local_volume() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Creating local GlusterFS volume $VOLUME_NAME...${NC}"
  echo -e "${SEPARATOR}"
  
  BRICKS="$NODE_IP:$BRICK_PATH"
  gluster volume create $VOLUME_NAME replica 2 $BRICKS force
  
  if [ $? -eq 0 ]; then
    gluster volume start $VOLUME_NAME
    echo -e "${GREEN}Volume $VOLUME_NAME created and started successfully.${NC}"
  else
    echo -e "${RED}Error: Failed to create volume $VOLUME_NAME. Please check settings.${NC}"
  fi
}

# Auto mount volume
function auto_mount_volume() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Checking and auto-mounting GlusterFS volume...${NC}"
  echo -e "${SEPARATOR}"
  
  if [ ! -d "$MOUNT_POINT" ]; then
    echo -e "${BLUE}Creating mount point directory: $MOUNT_POINT${NC}"
    mkdir -p $MOUNT_POINT
  fi
  
  if ! grep -q "$MOUNT_POINT" /etc/fstab; then
    echo -e "${BLUE}Adding mount entry to /etc/fstab...${NC}"
    mount -t glusterfs $NODE_IP:/$VOLUME_NAME $MOUNT_POINT
    echo "$NODE_IP:/$VOLUME_NAME $MOUNT_POINT glusterfs defaults,_netdev 0 0" >> /etc/fstab
  fi
  
  systemctl daemon-reload

  mount -a 2>&1 | tee /tmp/glusterfs-mount.log
  if mountpoint -q $MOUNT_POINT; then
    echo -e "${GREEN}GlusterFS volume mounted at $MOUNT_POINT.${NC}"
  else
    echo -e "${RED}Failed to mount GlusterFS volume, please check settings.${NC}"
    echo -e "${RED}Mount log output:${NC}"
    cat /tmp/glusterfs-mount.log
  fi
}

# Auto join cluster
function auto_join_cluster() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Auto-joining cluster...${NC}"
  echo -e "${SEPARATOR}"
  
  IFS=',' read -ra NODES <<< "$CLUSTER_NODES"
  for PEER in "${NODES[@]}"; do
    echo -e "${BLUE}Probing node $PEER...${NC}"
    gluster peer probe $PEER
  done

  check_and_create_volume
  auto_mount_volume
}

# Check and create volume if needed
function check_and_create_volume() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Checking volume status...${NC}"
  echo -e "${SEPARATOR}"
  
  if ! gluster volume info $VOLUME_NAME &> /dev/null; then
    echo -e "${BLUE}Volume $VOLUME_NAME not found, creating a new volume...${NC}"
    
    IFS=',' read -ra NODES <<< "$CLUSTER_NODES"
    PARAMETER_NODE_COUNT=${#NODES[@]}
    
    if [ -n "$MASTER_NODE" ]; then
      PARAMETER_NODE_COUNT=$((PARAMETER_NODE_COUNT + 1))
    fi

    PEER_COUNT=$(gluster peer status | grep -c 'Peer in Cluster')
    EFFECTIVE_NODE_COUNT=$((PEER_COUNT + PARAMETER_NODE_COUNT))

    if [ "$EFFECTIVE_NODE_COUNT" -ge 2 ]; then
      echo -e "${BLUE}Detected $EFFECTIVE_NODE_COUNT nodes (including peers and parameter-provided nodes) in the cluster.${NC}"
      
      BRICKS="$NODE_IP:$BRICK_PATH"
      for PEER in "${NODES[@]}"; do
        BRICKS="$BRICKS $PEER:$BRICK_PATH"
      done
      
      gluster volume create $VOLUME_NAME replica $EFFECTIVE_NODE_COUNT $BRICKS force
      
      if [ $? -eq 0 ]; then
        gluster volume start $VOLUME_NAME
        echo -e "${GREEN}Volume $VOLUME_NAME created and started successfully.${NC}"
      else
        echo -e "${RED}Error: Failed to create volume. Please check brick path and network connectivity.${NC}"
      fi
    else
      echo -e "${RED}Error: Not enough nodes connected or provided to create a replicated volume. At least two nodes are required.${NC}"
    fi
  else
    echo -e "${GREEN}Volume $VOLUME_NAME already exists.${NC}"
  fi
}

# Join node to existing cluster
# Join node to existing cluster
function join_node_to_cluster() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Joining this node to existing GlusterFS cluster...${NC}"
  echo -e "${SEPARATOR}"

  echo -e "${RED}Please ensure that this node's IP is not already part of the cluster.${NC}"
  echo -e "${BLUE}You can check the cluster's peer list on the master node with:${NC}"
  echo -e "${GREEN}gluster peer status${NC}"
  read -p "Press [Enter] to confirm you have verified this, or Ctrl+C to abort..."

  check_glusterfs_installed
  configure_firewall
  configure_glusterfs
  create_brick_directory

  echo -e "${BLUE}Attempting to join this node to master node $MASTER_NODE...${NC}"
  gluster peer probe $MASTER_NODE

  delete_existing_volume
  check_and_create_volume
  auto_mount_volume
}

# Delete existing volume
function delete_existing_volume() {
  if gluster volume info $VOLUME_NAME &> /dev/null; then
    echo -e "${SEPARATOR}"
    echo -e "${BLUE}Deleting existing volume $VOLUME_NAME...${NC}"
    echo -e "${SEPARATOR}"
    
    # Ensure the volume is stopped before deletion
    gluster volume stop $VOLUME_NAME force
    gluster volume delete $VOLUME_NAME
  else
    echo -e "${GREEN}No existing volume $VOLUME_NAME to delete.${NC}"
  fi
}

# Add node to existing cluster
function add_node_to_cluster() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Adding or joining this node to the GlusterFS cluster...${NC}"
  echo -e "${SEPARATOR}"

  echo -e "${RED}Please ensure that this node's IP is not already part of the cluster.${NC}"
  echo -e "${BLUE}You can check the cluster's peer list on the master node with:${NC}"
  echo -e "${GREEN}gluster peer status${NC}"
  read -p "Press [Enter] to confirm you have verified this, or Ctrl+C to abort..."

  check_glusterfs_installed
  configure_firewall
  configure_glusterfs
  create_brick_directory

  if [ -n "$CLUSTER_NODES" ]; then
    # Running on an existing node
    echo -e "${BLUE}Configuring existing node to add new nodes...${NC}"
    filter_local_ip
    auto_join_cluster
  elif [ -n "$MASTER_NODE" ]; then
    # Running on a new node
    echo -e "${BLUE}Joining this new node to the existing cluster via master node $MASTER_NODE...${NC}"
    gluster peer probe $MASTER_NODE

    check_and_create_volume
    auto_mount_volume
  else
    echo -e "${RED}Error: Either --cluster-nodes or --master-node must be provided for add-node operation.${NC}"
    show_help
    exit 1
  fi
}

# Rejoin node to cluster
function rejoin_node_to_cluster() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Rejoining this node to existing GlusterFS cluster...${NC}"
  echo -e "${SEPARATOR}"

  echo -e "${RED}Please ensure that this node's IP exist in the cluster.${NC}"
  echo -e "${BLUE}You can check the cluster's peer list on the master node with:${NC}"
  echo -e "${GREEN}gluster peer status${NC}"
  read -p "Press [Enter] to confirm you have verified this, or Ctrl+C to abort..."

  check_glusterfs_installed
  configure_firewall
  configure_glusterfs
  
  echo -e "${RED}Clearing old GlusterFS configuration...${NC}"
  reset_gluster  
  filter_local_ip

  echo -e "${RED}Please run the following command on other cluster nodes (e.g., on 10.1.1.122):${NC}"
  echo "$0 --link --master-node $NODE_IP"
  echo -e "${BLUE}After running the command on other nodes, press [Enter] to continue...${NC}"
  read -p ""

  echo -e "${BLUE}Auto-joining cluster...${NC}"
  auto_join_cluster
}

# Check if GlusterFS is installed
function check_glusterfs_installed() {
  if ! command -v gluster &> /dev/null; then
    echo -e "${RED}Error: GlusterFS is not installed. Please install GlusterFS first.${NC}"
    exit 1
  fi
}

# Reset GlusterFS configuration
function reset_gluster() {
  echo -e "${SEPARATOR}"
  echo -e "${BLUE}Resetting GlusterFS configuration...${NC}"
  echo -e "${SEPARATOR}"
  
  delete_existing_volume

  if mountpoint -q $MOUNT_POINT; then
    echo -e "${BLUE}Unmounting $MOUNT_POINT...${NC}"
    unmount_success=false
    max_attempts=5
    attempts=0

    while [ "$attempts" -lt "$max_attempts" ]; do
      umount $MOUNT_POINT
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}Unmounted $MOUNT_POINT successfully.${NC}"
        unmount_success=true
        break
      else
        echo -e "${RED}Failed to unmount $MOUNT_POINT. Retrying... (${attempts}/${max_attempts})${NC}"
        attempts=$((attempts + 1))
        sleep 2
      fi
    done

    if [ "$unmount_success" = false ]; then
      echo -e "${RED}Error: Could not unmount $MOUNT_POINT after multiple attempts. Please check the system and try again.${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}No mount point $MOUNT_POINT to unmount.${NC}"
  fi

  echo -e "${BLUE}Removing mount point directory: $MOUNT_POINT...${NC}"
  rm -rf $MOUNT_POINT

  echo -e "${BLUE}Clearing GlusterFS configuration...${NC}"
  rm -rf /var/lib/glusterd/*
  
  echo -e "${BLUE}Restarting GlusterFS service...${NC}"
  systemctl restart glusterd

  echo -e "${GREEN}GlusterFS configuration has been reset.${NC}"
}

# Function to process CLI arguments and execute the appropriate action
function process_cli() {
  if [ "$INITIALIZE" -eq 1 ]; then
    initialize_glusterfs
  elif [ "$ADD_NODE" -eq 1 ]; then
    add_node
  elif [ "$REJOIN" -eq 1 ]; then
    if [ -z "$CLUSTER_NODES" ]; then
      echo -e "${RED}Error: Rejoin operation requires --cluster-nodes option.${NC}"
      show_help
      exit 1
    fi
    rejoin_node_to_cluster
  elif [ "$LINK" -eq 1 ]; then
    if [ -z "$MASTER_NODE" ]; then
      echo -e "${RED}Error: Link operation requires --master-node option.${NC}"
      show_help
      exit 1
    fi
    link_node_to_cluster
  elif [ "$RESET" -eq 1 ]; then
    reset_gluster
    exit 0
  else
    # No parameters provided, display help
    show_help
    exit 0
  fi

  echo -e "${GREEN}GlusterFS configuration complete.${NC}"
}

function main() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --initialize) INITIALIZE=1 ;;
      --add-node) ADD_NODE=1 ;;
      --rejoin) REJOIN=1 ;;
      --reset) RESET=1 ;;
      --link) LINK=1 ;;
      --node-ip) NODE_IP="$2"; shift ;;
      --cluster-nodes) CLUSTER_NODES="$2"; shift ;;
      --master-node) MASTER_NODE="$2"; shift ;;
      --help) show_help; exit 0 ;;
      *) echo -e "${RED}Unknown parameter: $1${NC}"; show_help; exit 1 ;;
    esac
    shift
  done

  # Auto-detect NODE_IP if not provided
  if [ -z "$NODE_IP" ]; then
    NODE_IP=$(detect_ip)
    echo -e "${GREEN}Auto-detected local IP: $NODE_IP${NC}"
  fi

  # Process CLI and execute the appropriate action
  process_cli
}

# Execute CLI processing
main "$@"

