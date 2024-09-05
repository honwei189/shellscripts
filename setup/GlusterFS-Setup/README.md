# GlusterFS Cluster Setup and Maintenance Script

This script automates the setup, management, and maintenance of a GlusterFS cluster. It provides options to initialize a new cluster, add nodes, join an existing cluster, rejoin, reset configurations, and link nodes to the cluster. This guide offers detailed instructions for using the script and handling various scenarios, including server corruption or replacement.

## NOTE: Supported Operating Systems

This script is primarily designed for **Oracle Linux 9** and **CentOS 9**. While the GlusterFS repository officially supports CentOS 7 and 8, this script can also be used on CentOS 7 and 8, as well as Oracle Linux 7 and 8. Adjustments may be necessary depending on your specific operating environment and GlusterFS version.

## Table of Contents

- [Usage](#usage)
- [Options](#options)
- [Examples](#examples)
- [Important Notes](#important-notes)
- [Handling Specific Scenarios](#handling-specific-scenarios)
  - [Corrupted Server Reinstallation or Replacement](#corrupted-server-reinstallation-or-replacement)
  - [Rejoining a Node to an Existing Cluster](#rejoining-a-node-to-an-existing-cluster)
- [Troubleshooting](#troubleshooting)

## Usage

To run the script, execute the following command:

```bash
sh glusterfs-setup.sh [options]
```

## Options

### Initialization

- **`--initialize`**  
  Initialize GlusterFS on this node.
  - **`--volume-name <name>`**: (Optional) Set a custom volume name (default is `"myvolume"`).
  - **`--brick-path <path>`**: (Optional) Set a custom brick path (default is `"/data/.glusterfs"`).
  - **`--mount-point <path>`**: (Optional) Set a custom mount point (default is `"/mnt/glusterfs"`).
  - **`--cluster-nodes <IP1,IP2,...>`**: (Required) Comma-separated list of all cluster node IPs.

### Adding Nodes to an Existing Cluster

- **`--add-node`**  
  Add this node to an existing GlusterFS cluster.
  - **`--cluster-nodes <IP1,IP2,...>`**: (Required) Comma-separated list of all cluster node IPs.

### Joining an Existing Cluster

- **`--join-node`**  
  Join this node to an existing GlusterFS cluster.
  - **`--master-node <IP>`**: (Required) IP address of the master node to join.

### Rejoining a Cluster

- **`--rejoin`**  
  Rejoin this node to an existing GlusterFS cluster.
  - **`--cluster-nodes <IP1,IP2,...>`**: (Required) Comma-separated list of all cluster node IPs.

### Linking a Node to a Cluster

- **`--link`**  
  Link this node to the cluster and wait for the master node's confirmation.
  - **`--master-node <IP>`**: (Required) IP address of the master node to link.

### General Options

- **`--node-ip <IP>`**  
  Set the IP address of the current node (if different from the default).
  
- **`--reset`**  
  Reset the GlusterFS configuration on this node.

- **`--help`**  
  Show the help message.

## Examples

### Initialize a New Node

To initialize a new node with the GlusterFS setup:

```bash
sh glusterfs-setup.sh --initialize --cluster-nodes 10.1.1.210,10.1.1.122
```

### Add a Node to an Existing Cluster

To add a new node to an existing GlusterFS cluster:

```bash
sh glusterfs-setup.sh --add-node --cluster-nodes 10.1.1.210,10.1.1.122
```

### Join a Node to an Existing Cluster

To join a node to an existing cluster using the master node's IP:

```bash
sh glusterfs-setup.sh --join-node --master-node 10.1.1.210
```

### Rejoin a Node to a Cluster

To rejoin a node to a cluster after resetting configurations:

```bash
sh glusterfs-setup.sh --rejoin --cluster-nodes 10.1.1.210,10.1.1.122
```

### Link a Node to the Cluster

To link a new node to the cluster and wait for the master node to confirm:

```bash
sh glusterfs-setup.sh --link --master-node 10.1.1.210
```

### Reset GlusterFS Configuration

To reset the GlusterFS configuration on the current node:

```bash
sh glusterfs-setup.sh --reset
```

## Important Notes

1. **Running as Root**: This script must be run with root privileges. Ensure you have the necessary permissions before executing the script.

2. **Initialization**: When initializing a node, you must provide a list of cluster node IPs. After running the `--initialize` command, the script will prompt you to run the `--link` command on all other nodes that need to be added to the cluster.

3. **Adding Nodes**: Ensure that the IPs of the nodes you want to add are reachable from the master node and that the firewall settings allow communication on the required ports (24007-24008 and 49152-49251).

4. **Joining an Existing Cluster**: When joining an existing cluster, ensure that the master node IP is correct and reachable. The script will handle probing and connecting to the master node.

5. **Rejoining a Cluster**: If a node needs to rejoin a cluster after being disconnected, use the `--rejoin` option. This will reset the node's configuration and attempt to re-establish connections with the cluster nodes.

6. **Linking Nodes**: The `--link` option should be used on new nodes being added to a cluster. It will reset the node's configuration and wait for the master node to confirm the connection.

7. **Resetting Configuration**: Use the `--reset` option carefully. This will remove all existing GlusterFS configurations on the node and require re-initialization or rejoining of the cluster.

8. **Stale File Handles**: If you encounter issues such as "Stale file handle" errors, it may be due to filesystem corruption or a node being improperly removed from the cluster. A reboot or remount of the GlusterFS volume may resolve this issue, but in some cases, a reset and rejoin might be necessary.

## Handling Specific Scenarios

### Corrupted Server Reinstallation or Replacement

If a server in the GlusterFS cluster becomes corrupted or needs to be replaced, follow these steps:

1. **Reinstall or Replace the Server**: If a server is corrupted beyond repair, you may need to reinstall the operating system or replace the hardware entirely.

2. **Reinitialize the New Server**:
   - After reinstalling or replacing the server, install GlusterFS.
   - Use the script to initialize the server with the `--initialize` option.
   - Example:  
     ```bash
     sh glusterfs-setup.sh --initialize --cluster-nodes 10.1.1.210,10.1.1.122
     ```

3. **Link the New Server to the Cluster**:
   - On the new server, run the script with the `--link` option to prepare it for joining the existing cluster.
   - Example:
     ```bash
     sh glusterfs-setup.sh --link --master-node 10.1.1.210
     ```
   - The script will wait for the master node to confirm the connection.

4. **Confirm on Master Node**:
   - On the master node (the primary node in the cluster), run the script to add or rejoin the server to the cluster. Use the `--add-node` or `--rejoin` option depending on the scenario.
   - Example for adding a new node:
     ```bash
     sh glusterfs-setup.sh --add-node --cluster-nodes 10.1.1.210,10.1.1.122
     ```
   - Example for rejoining a node:
     ```bash
     sh glusterfs-setup.sh --rejoin --cluster-nodes 10.1.1.210,10.1.1.122
     ```

5. **Verify the Node Status**:
   - Ensure that the new or replaced server is properly connected and synchronized with the cluster by checking the status of the peers and volumes using GlusterFS commands:
   ```bash
   gluster peer status
   gluster volume info
   ```

6. **Handle Stale File Handles or Volume Issues**:
   - If you encounter "Stale file handle" errors, try unmounting the volume, resetting GlusterFS configuration on the node, and rejoining the cluster.

### Rejoining a Node to an Existing Cluster

If a node has been disconnected or removed from the cluster and needs to be rejoined:

1. **Reset the Node's Configuration**:
   - Use the script to reset the node's configuration with the `--reset` option.
   - Example:
     ```bash
     sh glusterfs-setup.sh --reset
     ```

2. **Rejoin the Cluster**:
   - Use the `--rejoin` option to rejoin the node to the cluster.
   - Example:
     ```bash
     sh glusterfs-setup.sh --rejoin --cluster-nodes

 10.1.1.210,10.1.1.122
     ```

3. **Verify and Test**:
   - Verify the node's status and volume synchronization using GlusterFS commands.

## Troubleshooting

- **GlusterFS Daemon Issues**: If the GlusterFS daemon (`glusterd`) fails to start or shows errors, check the logs in `/var/log/glusterfs/` for details and resolve any underlying issues.
- **Network Issues**: Ensure all nodes are reachable over the network and that firewall settings allow communication on the required ports.
- **File System Errors**: If encountering file system errors, consider checking the brick paths on each server for integrity. If necessary, unmount the GlusterFS volume, reset the configuration, and rejoin the cluster.

