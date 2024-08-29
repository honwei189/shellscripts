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
    ./install_mysql_galera.sh --initialize --mysql-root-password YourPassword --cluster-nodes 10.1.1.122,10.1.1.123

  Add a node to an existing cluster:
    ./install_mysql_galera.sh --add-node --cluster-nodes 10.1.1.122,10.1.1.123

Note:
  --initialize and --add-node cannot be used together.
  Ensure the cluster nodes are correctly listed in --cluster-nodes when adding a node.
