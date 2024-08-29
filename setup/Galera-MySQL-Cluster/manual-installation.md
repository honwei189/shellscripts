### MySQL + Galera Installation Guide (Including Automated Password Setup)

#### Why Use This Guide and Shell Script

This guide provides step-by-step instructions for installing MySQL with Galera on CentOS 8, 9 and Oracle Linux 8, 9. Galera provides a synchronous multi-master cluster for MySQL, which allows for high availability and redundancy. Due to Galera's lack of support for CentOS 7 and below, this guide focuses on installation in a supported environment. 

Using the provided shell script, you can automate the entire setup and configuration process. This automation reduces manual effort, minimizes errors, and ensures a consistent configuration across multiple nodes in your cluster. The script is designed to initialize a new Galera cluster or add a node to an existing cluster.

**Important Note**: Occasionally, when new versions of MySQL or Galera are released, the URLs for older versions may be removed from the official repositories. If you encounter download failures during the script execution, visit the [Galera Cluster Downloads page](https://galeracluster.com/downloads/) to download the latest version. You will then need to update the URLs in the shell script to match the new version.

#### 1. Preparation

**Operating Systems Supported**: CentOS 8, 9; Oracle Linux 8, 9

**Prerequisites**:
- Ensure the system is updated:

  ```bash
  sudo yum update -y
  ```

- Install required dependencies:

  ```bash
  sudo yum install -y libaio ncurses-compat-libs rsync lsof
  ```

#### 2. Remove Existing MySQL Installation

1. Stop and disable the current MySQL service:

   ```bash
   sudo systemctl stop mysqld
   sudo systemctl disable mysqld
   ```

2. Remove any installed MySQL packages:

   ```bash
   sudo yum remove -y mysql mysql-server
   ```

3. Delete MySQL data directories and configuration files:

   ```bash
   sudo rm -rf /var/lib/mysql
   sudo rm -rf /var/log/mysql
   sudo rm -f /etc/my.cnf
   ```

### 3. Check for MySQL User

Before proceeding, check if the MySQL user already exists. If not, you will need to create it.

**Check if the user exists:**

```bash
id -u mysql
```

If the user exists, this command will return the UID. If not, it will not return anything. If the user does not exist, you need to create it.

**Create the MySQL user:**

```bash
sudo useradd -r -s /bin/false mysql
```

This command creates a system user `mysql` with no login privileges, specifically for running the MySQL service.

---

### 4. Set MySQL Data Directory Permissions

Ensure that the MySQL user has the correct permissions for the data directory `/var/lib/mysql`:

```bash
sudo chown -R mysql:mysql /var/lib/mysql
```

#### 5. Download and Extract MySQL and Galera

1. Download MySQL WSREP and Galera:

   ```bash
   wget https://releases.galeracluster.com/mysql-wsrep-8.0/binary/mysql-wsrep-8.0.39-26.20-linux-x86_64.tar.gz
   wget https://releases.galeracluster.com/galera-4/binary/galera-4-26.4.20-Linux-x86_64.tar.gz
   ```

2. Extract the binaries:

   ```bash
   sudo mkdir -p /usr/local/mysql-wsrep /usr/local/galera
   sudo tar -xzf mysql-wsrep-8.0.39-26.20-linux-x86_64.tar.gz -C /usr/local/mysql-wsrep --strip-components=1
   sudo tar -xzf galera-4-26.4.20-Linux-x86_64.tar.gz -C /usr/local/galera --strip-components=1
   ```

#### 6. Create and Set Directory and File Permissions

1. Create MySQL data directory and set permissions:

   ```bash
   sudo mkdir -p /var/lib/mysql
   sudo chown mysql:mysql /var/lib/mysql
   sudo chmod 755 /var/lib/mysql
   ```

2. Create runtime directory and set permissions:

   ```bash
   sudo mkdir -p /var/run/mysqld
   sudo chown mysql:mysql /var/run/mysqld
   sudo chmod 755 /var/run/mysqld
   ```

3. Create a log file and set permissions:

   ```bash
   sudo touch /var/log/mysqld.log
   sudo chown mysql:mysql /var/log/mysqld.log
   sudo chmod 644 /var/log/mysqld.log
   ```

#### 7. Configure MySQL

1. Create the MySQL configuration file `/etc/my.cnf`:

   ```ini
   [client]
   socket=/var/lib/mysql/mysql.sock

   [mysqld]
   user=mysql
   basedir=/usr/local/mysql-wsrep
   datadir=/var/lib/mysql
   socket=/var/lib/mysql/mysql.sock
   log-error=/var/log/mysqld.log
   pid-file=/var/run/mysqld/mysqld.pid

   # Galera settings
   #wsrep_on=ON
   #wsrep_provider=/usr/local/galera/lib/libgalera_smm.so
   #wsrep_cluster_address=gcomm://<node1_ip>,<node2_ip>,<node3_ip>
   #wsrep_cluster_name="my_galera_cluster"
   #wsrep_node_address=CURRENT_SERVER_IP
   #wsrep_node_name=main
   #wsrep_sst_method=rsync

   # MySQL settings
   binlog_format=row
   default_storage_engine=InnoDB
   innodb_autoinc_lock_mode=2
   ```

   **Note**: During initial configuration, keep the `wsrep` settings commented out. After successfully starting the MySQL service for the first time, you can enable these settings as needed.

#### 8. Initialize MySQL Data Directory

1. Initialize the MySQL data directory:

   ```bash
   sudo /usr/local/mysql-wsrep/bin/mysqld --defaults-file=/etc/my.cnf --initialize --user=mysql
   ```

2. Check the log to get the initial root password:

   ```bash
   sudo cat /var/log/mysqld.log | grep 'temporary password'
   ```

#### 9. Configure systemd Service

1. Create a systemd service file for MySQL:

   ```bash
   sudo vi /etc/systemd/system/mysqld.service
   ```

   Content:

   ```ini
   [Unit]
   Description=MySQL 8.0 database server
   After=network.target
   Wants=network-online.target

   [Service]
   Type=forking
   ExecStartPre=/bin/mkdir -p /var/run/mysqld
   ExecStartPre=/bin/chown mysql:mysql /var/run/mysqld
   ExecStartPre=/bin/sleep 10
   ExecStart=/usr/local/mysql-wsrep/bin/mysqld --defaults-file=/etc/my.cnf --daemonize --pid-file=/var/run/mysqld/mysqld.pid
   ExecStop=/usr/local/mysql-wsrep/bin/mysqladmin shutdown
   PIDFile=/var/run/mysqld/mysqld.pid
   User=mysql
   Group=mysql
   Restart=on-failure
   TimeoutSec=300

   [Install]
   WantedBy=multi-user.target
   ```

2. Reload systemd and start the MySQL service:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable mysqld
   sudo systemctl start mysqld
   ```

#### 10. Add MySQL Binary Directory to Global PATH Environment Variable

1. Edit the `/etc/profile` file:

   ```bash
   sudo vi /etc/profile
   ```

2. Add the following line to include the MySQL WSREP binary directory in the PATH:

   ```bash
   export PATH=$PATH:/usr/local/mysql-wsrep/bin
   ```

3. Save the file and reload the configuration:

   ```bash
   source /etc/profile
   ```

#### 11. Verify Installation and Configuration

1. Check the status of the MySQL service:

   ```bash
   sudo systemctl status mysqld
   ```

2. Log into MySQL and change the root user password:

   ```bash
   mysqladmin -u root --password='current_password' password ''
   ```

3. Check the log to verify service status:

   ```bash
   sudo cat /var/log/mysqld.log
   ```

### Configure MySQL Galera Master-Master Cluster

To configure a MySQL Galera Master-Master cluster, the following steps need to be performed on all nodes. These steps assume you have already installed and configured MySQL and Galera following the previous instructions.

#### 1. Configure Firewall (Optional)

1. Open the necessary ports for Galera and MySQL:

   ```bash
   sudo firewall-cmd --permanent --add-port=4567/tcp
   sudo firewall-cmd --permanent --add-port=4568/tcp
   sudo firewall-cmd --permanent --add-port=4444/tcp
   sudo firewall-cmd --permanent --add-port=3306/tcp
   sudo firewall-cmd --reload
   ``

`

#### 2. Configure MySQL and Galera

1. Edit the `/etc/my.cnf` file to ensure each node's configuration includes the following settings:

   ```ini
   [mysqld]
   wsrep_on=ON
   wsrep_provider=/usr/local/galera/lib/libgalera_smm.so
   wsrep_cluster_address=gcomm://<node1_ip>,<node2_ip>,<node3_ip>
   wsrep_cluster_name="my_galera_cluster"
   wsrep_node_address=<this_node_ip>
   wsrep_node_name=<this_node_name>
   wsrep_sst_method=rsync

   binlog_format=row
   default_storage_engine=InnoDB
   innodb_autoinc_lock_mode=2
   ```

   - Replace `<node1_ip>, <node2_ip>, <node3_ip>` with the actual cluster node IPs.
   - Replace `<this_node_ip>` with the IP address of the current node.
   - Replace `<this_node_name>` with the name of the current node.

2. Save the file and restart the MySQL service:

   ```bash
   sudo systemctl stop mysqld
   /usr/local/mysql-wsrep/bin/mysqld --wsrep-new-cluster --defaults-file=/etc/my.cnf --daemonize --pid-file=/var/run/mysqld/mysqld.pid --user=mysql --console -v
   ```

#### 3. Start Galera Cluster

**On the first node:**

1. Initialize and start the Galera cluster on the first node:

   ```bash
   sudo /usr/local/mysql-wsrep/bin/mysqld --wsrep-new-cluster --defaults-file=/etc/my.cnf --daemonize --pid-file=/var/run/mysqld/mysqld.pid --user=mysql
   ```

2. Verify the cluster status:

   ```bash
   mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
   ```

   The output should show the cluster size as 1.

**On other nodes:**

1. Start the MySQL service on other nodes to join the cluster:

   ```bash
   sudo systemctl start mysqld
   ```

2. Verify the cluster status:

   ```bash
   mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
   ```

   The output should incrementally increase until all nodes have joined.

#### 4. Verify Master-Master Configuration

1. On any node, create a test database or table:

   ```bash
   mysql -u root -p -e "CREATE DATABASE test_db;"
   ```

2. Verify that the database has been automatically created on other nodes:

   ```bash
   mysql -u root -p -e "SHOW DATABASES LIKE 'test_db';"
   ```

   If the cluster is configured correctly, the database should appear on all nodes.

#### 5. Monitoring and Maintenance

1. Regularly check the cluster status:

   ```bash
   mysql -u root -p -e "SHOW STATUS LIKE 'wsrep%';"
   ```

2. If you need to scale the cluster or adjust configuration, ensure all node configuration files remain synchronized.

3. If any node encounters an issue, restart it and ensure it rejoins the cluster.

#### Troubleshooting

- **Invalid data directory**: Ensure `/var/lib/mysql` exists and has the correct permissions.
- **MySQL fails to start**: Check the `/var/log/mysqld.log` file for detailed error information.
- **Firewall issues**: Ensure necessary ports are open and correct firewall rules are applied.

---

By following this guide and using the provided shell script, you can easily automate the setup and configuration of a MySQL Galera cluster, ensuring high availability and redundancy in your database environment.