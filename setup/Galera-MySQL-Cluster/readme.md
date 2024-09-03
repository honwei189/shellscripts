# MySQL + Galera Installation Guide and Automation Script

## Introduction

This repository provides a comprehensive guide and automation script for setting up a MySQL + Galera Cluster on CentOS 8/9 or Oracle Linux 8/9. The script automates the installation, configuration, and addition of nodes to a Galera cluster. Due to Galera's lack of support for CentOS 7 and earlier versions, this guide focuses on the appropriate installation methods for the supported operating systems.

## Features

- Automated installation of MySQL WSREP and Galera on supported Linux distributions.
- Initialization of a new MySQL + Galera node.
- Adding a new node to an existing Galera cluster.
- Customizable options for cluster setup, including cluster name and node IP addresses.
- Automatic firewall configuration to allow necessary ports for MySQL and Galera.
- Manual backup options for existing MySQL databases before reinstallation.
- Dynamic handling of different MySQL WSREP and Galera versions, with prompts to download if URLs are outdated.

## Requirements

- **Operating Systems**: CentOS 8/9, Oracle Linux 8/9
- **Dependencies**: `libaio`, `ncurses-compat-libs`, `rsync`, `lsof`, `wget`, `firewalld`

## Usage

### Script Parameters

```plaintext
Usage:
  ./setup-galera-mysql.sh [options]

Options for Initialization:
  --initialize                         Initialize MySQL and Galera on this node. Must be used with the following options:
    --mysql-root-password <password>    Set the MySQL root password.
    --cluster-nodes <IP1,IP2,...>       Comma-separated list of all cluster node IPs.
    --cluster-name <name>               (Optional) Set a custom cluster name (default is "my_galera_cluster").

Options for Adding Nodes to an Existing Cluster:
  --add-node                            Add this node to an existing Galera cluster. Must be used with the following options:
    --cluster-nodes <IP1,IP2,...>       Comma-separated list of all cluster node IPs.
    --cluster-name <name>               (Optional) Set a custom cluster name (default is "my_galera_cluster").

General Options:
  --node-ip <IP>                        Set the IP address of the current node (if different from the default).
  --replication-mode <mode>             Set replication mode: master-master or master-slave.
  --force                               Force the operation (use with caution).
  --help                                Show this help message.

Examples:
  Initialize a new node:
    ./setup-galera-mysql.sh --initialize --mysql-root-password YourPassword --cluster-nodes 10.1.1.122,10.1.1.123

  Add a node to an existing cluster:
    ./setup-galera-mysql.sh --add-node --cluster-nodes 10.1.1.122,10.1.1.123

Note:
  --initialize and --add-node cannot be used together.
  Ensure the cluster nodes are correctly listed in --cluster-nodes when adding a node.
```

---


# Important Note: Avoid Simultaneous Reboots in Galera Cluster

**Warning**: It is highly recommended not to reboot all nodes in a Galera Cluster simultaneously. Doing so can cause serious synchronization issues, leading to potential data inconsistency, cluster failure, or even data loss.

## Why Should You Avoid Simultaneous Reboots?

1. **Cluster Synchronization Issues**: Galera Cluster relies on synchronization between nodes to maintain data consistency. If all nodes are rebooted at the same time, the cluster may be unable to determine which node has the most up-to-date data, especially if no node was designated as the primary during the reboot.

2. **State Recovery Problems**: When a node starts up, it needs to obtain the current state from another active node in the cluster. If all nodes are down or booting up at the same time, they cannot synchronize their states, potentially leading to cluster formation failures or inconsistencies.

3. **Risk of Split-Brain Scenarios**: If multiple nodes rejoin the cluster without proper coordination, a "split-brain" scenario may occur, where nodes have conflicting data states, resulting in data inconsistency across the cluster.

4. **Risk of Data Corruption or Loss**: If all nodes encounter issues (such as file locking or configuration errors) during the reboot process, there is a heightened risk of data corruption or even complete database startup failure.

## Recommended Reboot Procedure

To safely reboot a Galera Cluster, follow these steps:

1. **Reboot Nodes Sequentially**: Reboot one node at a time. Wait until the rebooted node is fully up and successfully rejoined the cluster before rebooting the next node.

2. **Check Cluster Status After Each Reboot**: After rebooting each node, check the cluster status to ensure it is in a consistent state. You can use the following command:

   ```bash
   mysql -u root -p -e "SHOW STATUS LIKE 'wsrep%';"
   ```

   Ensure that `wsrep_cluster_size` matches the expected number of nodes and that all nodes show as `SYNCED`.

3. **Graceful Shutdown and Startup**: Use `systemctl stop mysqld` to gracefully shut down the MySQL service and `systemctl start mysqld` to start it again, avoiding forced shutdowns that might lead to data inconsistency.

4. **Keep at Least One Node Running**: Always keep at least one node running during the entire cluster reboot process. This node will serve as the source of synchronization for the other nodes.

By following these steps, you can ensure a safe and consistent Galera Cluster reboot process, preventing potential issues that may arise from simultaneous reboots.

---

## Recommended Recovery Steps if MySQL WSREP Service Fails After Reboot

If you encounter issues starting the MySQL WSREP service after a reboot or due to other errors, follow these steps to recover:

1. **Delete MySQL Data Directories:**

   ```bash
   sudo rm -rf /var/lib/mysql
   sudo rm -rf /var/run/mysqld
   ```

2. **Create and Set Directory and File Permissions:**

   - Create MySQL data directory and set permissions:

     ```bash
     sudo mkdir -p /var/lib/mysql
     sudo chown mysql:mysql /var/lib/mysql
     sudo chmod 755 /var/lib/mysql
     ```

   - Create runtime directory and set permissions:

     ```bash
     sudo mkdir -p /var/run/mysqld
     sudo chown mysql:mysql /var/run/mysqld
     sudo chmod 755 /var/run/mysqld
     ```

3. **Start MySQL Service:**

   ```bash
   sudo systemctl start mysqld
   ```

   If the service fails to start, proceed with the following steps:

4. **Initialize the MySQL Data Directory:**

   ```bash
   /usr/local/mysql-wsrep/bin/mysqld --defaults-file=/etc/my.cnf --initialize-insecure --user=mysql --console -v
   ```

   Then, attempt to start the MySQL service again:

   ```bash
   sudo systemctl start mysqld
   ```

5. **Start with Debugging (if the service still fails to start):**

   ```bash
   /usr/local/mysql-wsrep/bin/mysqld --defaults-file=/etc/my.cnf --daemonize --pid-file=/var/run/mysqld/mysqld.pid --user=mysql --console -v
   ```

### Conclusion

To avoid these issues, **always reboot nodes one at a time** and ensure that the remaining nodes are operational and synced with the cluster before proceeding to the next. This approach ensures the stability and consistency of your Galera Cluster.
