#!/bin/sh
###
 # @description       : Install Oracle Linux 9.x necessary softwares, PHP and mySQL
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 27/02/2024 10:52:08
 # @last modified     : 17/02/2024 10:52:21
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###
/usr/sbin/setenforce 0 2>&1 >/dev/null
sed -i 's/SELINUX=enforcing/#SELINUX=enforcing\nSELINUX=disabled/g' /etc/selinux/config

# firewall-cmd --permanent --add-source=192.168.1.0/24 --zone=trusted
# firewall-cmd --permanent --add-service=ssh/tcp --zone trusted
firewall-cmd --permanent --add-port=22/tcp --zone trusted
# firewall-cmd --permanent --remove-service=ssh --zone public
# firewall-cmd --permanent --add-port=3306/tcp --zone trusted

firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https

firewall-cmd --permanent --add-port=25/tcp --permanent
firewall-cmd --permanent --add-port=25/udp --permanent

firewall-cmd --reload

ln -s /usr/bin/firewall-cmd /usr/bin/fw


### Disable IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p


### Disable IPv6 from SSH
sed -i 's/^#AddressFamily any/#AddressFamily any\nAddressFamily inet/' /etc/ssh/sshd_config
sed -i 's/^#ListenAddress 0.0.0.0/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
service sshd restart


cd /etc/pki/rpm-gpg/

dnf install epel-release epel-next-release -y
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm

dnf config-manager --enable ol9_codeready_builder

dnf install ImageMagick-c++ wget bzip2 tar gcc gcc-c++ git svn wget vim net-tools -y
dnf group -y install "Development Tools"

dnf module reset php -y
dnf module enable php:remi-8.2 -y

dnf install screen htop sendmail chkconfig unzip nginx bind-utils tmpwatch nfs-utils gcc.x86_64 pcre-devel.x86_64 openssl-devel.x86_64 GeoIP GeoIP-devel GeoIP-data zlib-devel GeoIP GeoIP-devel GeoIP-data -y

dnf install php php-fpm php-cli php-json php-common php-mysql php-pdo php-curl php-dom php-simplexml php-xml php-xmlrpc php-xmlreader php-curl php-date php-exif php-filter php-ftp php-gd php-hash php-iconv php-json php-libxml php-pecl-imagick php-mbstring php-mysqlnd php-openssl php-pcre php-posix php-sockets php-spl php-tokenizer php-zlib php-pecl-zip php-brotli php-redis -y
dnf install mysql mysql-server -y

# AlmaLinux 9.5 - New version of openssl is causing SSH server errors due to an openssl version mismatch
dnf remove openssh-server openssh-clients -y
dnf install openssh-server openssh-clients -y

# Switch to using BBR to address bandwidth performance issues and reduce the problem of high latency.
sysctl net.ipv4.tcp_congestion_control=bbr
sysctl net.ipv4.tcp_congestion_control # Verify that the BBR setting is activated.


chkconfig sendmail on
service sendmail start

#echo "" >> /etc/aliases
#echo "" >> /etc/aliases
#echo -e "root:\t\tYOUR_EMAIL_ADDRESS" >> /etc/aliases

dnf install php-devel -y


echo "deflog on" >> /root/.screenrc
echo "logfile /tmp/screenlog.%n" >> /root/.screenrc
echo "" >> /root/.screenrc
echo "termcapinfo xterm* 'is=\E[r\E[m\E[2J\E[H\E[?7h\E[?1;4;6l'" >> /root/.screenrc

sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/g' /etc/ssh/sshd_config

dnf install p7zip p7zip-plugins -y


### Install Fail2ban
dnf install whois fail2ban fail2ban-systemd -y
echo "[DEFAULT]" >> /etc/fail2ban/jail.local
echo "ignoreip = 127.0.0.1/8 192.168.1.0/24" >> /etc/fail2ban/jail.local
echo "" >> /etc/fail2ban/jail.local
echo "# An ip address/host is banned if it has generated \"maxretry\" during the last \"findtime\" seconds." >> /etc/fail2ban/jail.local
echo "#bantime  = -1" >> /etc/fail2ban/jail.local
echo "bantime = 31536000" >> /etc/fail2ban/jail.local
echo "# Default 600 seconds reached the maxretry then block" >> /etc/fail2ban/jail.local
echo "findtime = 600" >> /etc/fail2ban/jail.local
echo "maxretry = 2" >> /etc/fail2ban/jail.local
echo "action = %(action_mwl)s" >> /etc/fail2ban/jail.local
echo "#destemail = yourname@your_domain" >> /etc/fail2ban/jail.local
echo "sendername = SysAlarm" >> /etc/fail2ban/jail.local
echo "" >> /etc/fail2ban/jail.local
echo "" >> /etc/fail2ban/jail.local
echo "#[fail2ban-ssh] # second jail: check every hour" >> /etc/fail2ban/jail.local
echo "#enabled = true" >> /etc/fail2ban/jail.local
echo "#filter = fail2ban-ssh" >> /etc/fail2ban/jail.local
echo "#logpath = /var/log/fail2ban.log" >> /etc/fail2ban/jail.local
echo "#action = iptables-multiport" >> /etc/fail2ban/jail.local
echo "echo "#maxretry = 2" >> /etc/fail2ban/jail.local
echo "#findtime = 1800" >> /etc/fail2ban/jail.local
echo "findtime = 10" >> /etc/fail2ban/jail.local
echo "#bantime = 86400     # ban for a day" >> /etc/fail2ban/jail.local
echo "" >> /etc/fail2ban/jail.local
echo "" >> /etc/fail2ban/jail.local
echo "[sshd]" >> /etc/fail2ban/jail.local
echo "enabled = true" >> /etc/fail2ban/jail.local
echo "filter  = sshd" >> /etc/fail2ban/jail.local
echo "port    = 22" >> /etc/fail2ban/jail.local
echo "action = %(action_mwl)s" >> /etc/fail2ban/jail.local
echo "logpath = /var/log/secure" >> /etc/fail2ban/jail.local
echo "bantime = -1" >> /etc/fail2ban/jail.local
echo "maxretry = 2" >> /etc/fail2ban/jail.local
echo "" >> /etc/fail2ban/jail.local
echo "[http]" >> /etc/fail2ban/jail.local
echo "enabled = true" >> /etc/fail2ban/jail.local
echo "port = http,https" >> /etc/fail2ban/jail.local
echo "filter = http" >> /etc/fail2ban/jail.local
echo "action = %(action_mwl)s" >> /etc/fail2ban/jail.local
echo "maxretry = 20" >> /etc/fail2ban/jail.local
echo "findtime = 60" >> /etc/fail2ban/jail.local
echo "#bantime = 3600" >> /etc/fail2ban/jail.local
echo "bantime = -1" >> /etc/fail2ban/jail.local
echo "logpath = %(nginx_access_log)s" >> /etc/fail2ban/jail.local
echo "          %(apache_access_log)s" >> /etc/fail2ban/jail.local
echo "" >> /etc/fail2ban/jail.local
##echo "[http2]" >> /etc/fail2ban/jail.local
##echo "enabled = true" >> /etc/fail2ban/jail.local
##echo "port = https" >> /etc/fail2ban/jail.local
##echo "filter = http2" >> /etc/fail2ban/jail.local
##echo "action = %(action_mwl)s" >> /etc/fail2ban/jail.local
##echo "maxretry = 20" >> /etc/fail2ban/jail.local
##echo "findtime = 60" >> /etc/fail2ban/jail.local
##echo "#bantime = 3600" >> /etc/fail2ban/jail.local
##echo "bantime = -1" >> /etc/fail2ban/jail.local
##echo "logpath = /var/log/nginx/access.log" >> /etc/fail2ban/jail.local


##sed -i 's/banaction = firewallcmd-ipset[actiontype=<multiport>]/#banaction = firewallcmd-ipset[actiontype=<multiport>]/g' /etc/fail2ban/jail.d/00-firewalld.conf
##sed -i 's/banaction_allports = firewallcmd-ipset[actiontype=<allports>]/#banaction_allports = firewallcmd-ipset[actiontype=<allports>]/g' /etc/fail2ban/jail.d/00-firewalld.conf
echo "" >> /etc/fail2ban/jail.d/00-firewalld.conf
echo "#actionban = firewall-cmd --add-source=<ip> --zone=drop && firewall-cmd --add-source=<ip> --zone=drop --permanent" >> /etc/fail2ban/jail.d/00-firewalld.conf
echo "#actionunban = firewall-cmd --remove-source=<ip> --zone=drop && firewall-cmd --remove-source=<ip> --zone=drop --permanent" >> /etc/fail2ban/jail.d/00-firewalld.conf

# touch /etc/fail2ban/jail.d/firewallcmd.conf

# echo "[INCLUDES]" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "before =" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "[Definition]" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "actionstart = firewall-cmd --permanent --new-ipset=fail2ban-<name> --type=hash:ip --option=timeout=<bantime>" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "              firewall-cmd --reload" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "actionstop = firewall-cmd --permanent --delete-ipset=fail2ban-<name>" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "             firewall-cmd --reload" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "             ipset flush fail2ban-<name>" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "             ipset destroy fail2ban-<name>" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "actionban = ipset add fail2ban-<name> <ip> timeout <bantime> -exist" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "" >> /etc/fail2ban/jail.d/firewallcmd.conf
# echo "actionunban = ipset del fail2ban-<name> <ip> -exist" >> /etc/fail2ban/jail.d/firewallcmd.conf

touch /etc/fail2ban/filter.d/http.conf
#touch /etc/fail2ban/filter.d/http2.conf

echo "[Definition]" >> /etc/fail2ban/filter.d/http.conf
#echo "failregex = <HOST> -.*- .*HTTP/1.* .* .*$" >> /etc/fail2ban/filter.d/http.conf
echo "failregex = <HOST> -.*- .*HTTP/[123].* .* .*$" >> /etc/fail2ban/filter.d/http.conf
echo "ignoreregex =" >> /etc/fail2ban/filter.d/http.conf
echo "" >> /etc/fail2ban/filter.d/http.conf


#echo "[Definition]" >> /etc/fail2ban/filter.d/http2.conf
#echo "failregex = <HOST> -.*- .*HTTP/2.* .* .*$" >> /etc/fail2ban/filter.d/http2.conf
#echo "ignoreregex =" >> /etc/fail2ban/filter.d/http2.conf
#echo "" >> /etc/fail2ban/filter.d/http2.conf

chkconfig fail2ban on
service fail2ban start




mkdir -p /data/tmp
sed -i 's/;sys_temp_dir = "\/tmp"/;sys_temp_dir = "\/tmp"\nsys_temp_dir = "\/data\/tmp"/g' /etc/php.ini
sed -i 's/;upload_tmp_dir =/;upload_tmp_dir =\nupload_tmp_dir = "\/data\/tmp"/g' /etc/php.ini
sed -i 's/expose_php = On/expose_php = Off/g' /etc/php.ini
sed -i 's/short_open_tag = Off/short_open_tag = On/g' /etc/php.ini
sed -i 's/;realpath_cache_size = 16k/;realpath_cache_size = 16k\nrealpath_cache_size = 256k/g' /etc/php.ini
sed -i 's/;realpath_cache_ttl = 120/;realpath_cache_ttl = 120\nrealpath_cache_ttl = 180/g' /etc/php.ini
sed -i 's/;date.timezone =/date.timezone = Asia\/Kuala_Lumpur/g' /etc/php.ini
sed -i 's/;max_input_vars = 1000/;max_input_vars = 1000\nmax_input_vars = 10000/g' /etc/php.ini
sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /etc/php.ini
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 8000M/g' /etc/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 8000M/g' /etc/php.ini


sed -i 's/pm.max_children = 50/;pm.max_children = 50\npm.max_children = 800/g' /etc/php-fpm.d/www.conf
sed -i 's/pm.start_servers = 5/;pm.start_servers = 5\npm.start_servers = 200/g' /etc/php-fpm.d/www.conf
sed -i 's/pm.min_spare_servers = 5/;pm.min_spare_servers = 5\npm.min_spare_servers = 1/g' /etc/php-fpm.d/www.conf
sed -i 's/pm.max_spare_servers = 35/;pm.max_spare_servers = 35\npm.max_spare_servers = 800/g' /etc/php-fpm.d/www.conf
sed -i 's/pm.max_requests = 500/;pm.max_requests = 500\npm.max_requests = 4000/g' /etc/php-fpm.d/www.conf
sed -i 's/;rlimit_files = 1024/;rlimit_files = 1024\nrlimit_files = 51200/g' /etc/php-fpm.d/www.conf
sed -i 's/;listen.backlog = 511/;listen.backlog = 511\nlisten.backlog = 65536/g' /etc/php-fpm.d/www.conf
sed -i 's/;request_slowlog_timeout = 0/;request_slowlog_timeout = 0\nrequest_slowlog_timeout = 10/g' /etc/php-fpm.d/www.conf


mkdir -p /usr/local/src/php/modules/

#cd /usr/local/src/php/modules/
#wget https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz
#tar xvfz ioncube_loaders_lin_x86-64.tar.gz
#cd ioncube
#cp -Rp ioncube_loader_lin_8.2.so /usr/lib64/php/modules/
#echo "zend_extension = ioncube_loader_lin_8.2.so" >> /etc/php.d/00-ioncube.ini



cd /usr/local/src/php/modules/
mkdir sourceguardian && cd sourceguardian
#wget loaders.linux-x86_64.tar.gz #download from https://www.sourceguardian.com/loaders.html
#wget https://github.com/honwei189/shellscripts/raw/master/php/loaders.linux-x86_64.tar.gz
curl https://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz -o loaders.linux-x86_64.tar.gz
tar xvfz loaders.linux-x86_64.tar.gz
cp ixed.8.2.lin /usr/lib64/php/modules/
echo "zend_extension = ixed.8.2.lin" >> /etc/php.d/00-sourceguardian.ini


sed -i 's/;opcache.enable_cli=0/;opcache.enable_cli=0\nopcache.enable_cli=1/g' /etc/php.d/10-opcache.ini
sed -i 's/;opcache.optimization_level=0x7FFEBFFF/;;opcache.optimization_level=0x7FFEBFFF\n;opcache.optimization_level=-1/g' /etc/php.d/10-opcache.ini
sed -i 's/;opcache.validate_timestamps=1/opcache.validate_timestamps=1/g' /etc/php.d/10-opcache.ini
sed -i 's/;opcache.use_cwd=1/opcache.use_cwd=1/g' /etc/php.d/10-opcache.ini
sed -i 's/opcache.max_accelerated_files=4000/;opcache.max_accelerated_files=4000\nopcache.max_accelerated_files=100000/g' /etc/php.d/10-opcache.ini
sed -i 's/;opcache.max_wasted_percentage=5/opcache.max_wasted_percentage=5/g' /etc/php.d/10-opcache.ini
sed -i 's/;opcache.consistency_checks=0/;opcache.consistency_checks=0\nopcache.consistency_checks=1/g' /etc/php.d/10-opcache.ini
sed -i 's/;opcache.huge_code_pages=0/;opcache.huge_code_pages=0\nopcache.huge_code_pages=1/g' /etc/php.d/10-opcache.ini
sed -i 's/;opcache.file_cache=/;opcache.file_cache=\nopcache.file_cache=1/g' /etc/php.d/10-opcache.ini

echo "opcache.fast_shutdown=1" >> /etc/php.d/10-opcache.ini
echo "opcache.revalidate_freq=60" >> /etc/php.d/10-opcache.ini

if [ ! -f "/usr/lib/systemd/system/php-fpm.service" ]; then
  echo "# It's not recommended to modify this file in-place, because it" >> /usr/lib/systemd/system/php-fpm.service
  echo "# will be overwritten during upgrades.  If you want to customize," >> /usr/lib/systemd/system/php-fpm.service
  echo "# the best way is to use the "systemctl edit" command." >> /usr/lib/systemd/system/php-fpm.service
  echo "" >> /usr/lib/systemd/system/php-fpm.service
  echo "[Unit]" >> /usr/lib/systemd/system/php-fpm.service
  echo "Description=The PHP FastCGI Process Manager" >> /usr/lib/systemd/system/php-fpm.service
  echo "After=syslog.target network.target" >> /usr/lib/systemd/system/php-fpm.service
  echo "" >> /usr/lib/systemd/system/php-fpm.service
  echo "[Service]" >> /usr/lib/systemd/system/php-fpm.service
  echo "Type=notify" >> /usr/lib/systemd/system/php-fpm.service
  echo "ExecStart=/usr/sbin/php-fpm --nodaemonize" >> /usr/lib/systemd/system/php-fpm.service
  echo "ExecReload=/bin/kill -USR2 $MAINPID" >> /usr/lib/systemd/system/php-fpm.service
  echo "PrivateTmp=true" >> /usr/lib/systemd/system/php-fpm.service
  echo "RuntimeDirectory=php-fpm" >> /usr/lib/systemd/system/php-fpm.service
  echo "RuntimeDirectoryMode=0755" >> /usr/lib/systemd/system/php-fpm.service
  echo "" >> /usr/lib/systemd/system/php-fpm.service
  echo "[Install]" >> /usr/lib/systemd/system/php-fpm.service
  echo "WantedBy=multi-user.target" >> /usr/lib/systemd/system/php-fpm.service

  chmod 644 /usr/lib/systemd/system/php-fpm.service
fi

chkconfig mysqld on
service mysqld start
chkconfig php-fpm on
service php-fpm start



php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
HASH="$(wget -q -O - https://composer.github.io/installer.sig)"
php -r "if (hash_file('SHA384', 'composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
chmod +x /usr/local/bin/composer

my_cnf=$my_cnf"\n#bind_address                           = 0.0.0.0"
my_cnf=$my_cnf"\ndefault-authentication-plugin           = mysql_native_password"
my_cnf=$my_cnf"\ncollation-server                        = utf8mb4_0900_ai_ci"
my_cnf=$my_cnf"\ninit-connect                            = 'SET NAMES utf8mb4'"
my_cnf=$my_cnf"\ncharacter-set-server                    = utf8mb4"
my_cnf=$my_cnf"\nskip-character-set-client-handshake     = true"
my_cnf=$my_cnf"\ntmpdir                                  = /tmp"
my_cnf=$my_cnf"\nskip_external_locking"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\nslow_query_log                          = 0"
my_cnf=$my_cnf"\nslow-query_log_file                     = /var/log/mysql-slow.log"
my_cnf=$my_cnf"\nlong_query_time                         = 2"
my_cnf=$my_cnf"\nmax_connections                         = 3000"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n## Raise to 128M for 2GB RAM, 256M for 4GB RAM and 512M for 8GB RAM"
my_cnf=$my_cnf"\nkey_buffer_size                         = 128M"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n## Raise to 128M for 2GB RAM, 256M for 4GB RAM and 512M for 8GB RAM"
my_cnf=$my_cnf"\ninnodb_buffer_pool_size                 = 128M"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n## Misc Tunables (Don't touch these unless you know why you would want to touch these)##"
my_cnf=$my_cnf"\n#max_allowed_packet                     = 16M"
my_cnf=$my_cnf"\nmax_allowed_packet                      = 256M"
my_cnf=$my_cnf"\ninnodb_file_per_table"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n## Changing this setting requires you to stop MySQL, move the current logs out of the way, and then starting MySQL ##"
my_cnf=$my_cnf"\ninnodb_log_file_size                    = 128M"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\ninnodb_thread_concurrency               = 0"
my_cnf=$my_cnf"\ninnodb_concurrency_tickets              = 8"
my_cnf=$my_cnf"\ninnodb_read_io_threads                  = 8"
my_cnf=$my_cnf"\ninnodb_write_io_threads                 = 8"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n#Remove all default SQL mode to prevent SQL errors"
my_cnf=$my_cnf"\nsql_mode                                = \"\""
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\n# Disabling symbolic-links is recommended to prevent assorted security risks"
my_cnf=$my_cnf"\n"
my_cnf=$my_cnf"\nsymbolic-links                          = 0"
my_cnf=$my_cnf"\n"

sed -i "s|pid-file=/run/mysqld/mysqld.pid|pid-file=/run/mysqld/mysqld.pid\n$my_cnf|g" /etc/my.cnf.d/mysql-server.cnf
sed -i "s|\[mysqld\]|\[mysql\]\ndefault-character-set                    = utf8mb4\n\n\[mysqld\]|g" /etc/my.cnf.d/mysql-server.cnf

touch /var/log/mysql-slow.log
chown -R mysql.mysql /var/log/mysql-slow.log

mysql -e "CREATE USER 'root'@'%' IDENTIFIED BY ''"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%';"


cd /usr/local/src/
git clone https://github.com/neurobin/shc.git
cd shc
./configure
./autogen.sh
make
make install

dnf install python3-pip go-toolset -y
pip3 install speedtest-cli


wget https://go.dev/dl/go1.23.3.linux-amd64.tar.gz
tar -zxvf go1.23.3.linux-amd64.tar.gz
mv go /usr/local/

cat << 'EOF' >> ~/.bashrc
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
EOF

source ~/.bash_profile
mkdir $HOME/go


echo "" >> /etc/ssh/sshd_config
echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> /etc/ssh/sshd_config
echo "" >> /etc/ssh/sshd_config

sed -i "s|#PubkeyAuthentication yes|PermitRootLogin yes\nPubkeyAuthentication yes|g" /etc/ssh/sshd_config
service sshd restart

##########

echo "Create an user as root"
echo ""
echo -n "Enter your username and press [ENTER]: "
read var_username

if [ "$var_username" == "" ]
then
    echo "Skip ..."
else
    #echo -n "Enter your password and press [ENTER]: "
    read -s -p "Enter your password and press [ENTER]: " var_password

    if [ ! -z "$var_password" ]
    then
        egrep "^$username" /etc/passwd >/dev/null
        if [ ! $? -eq 0 ]; then
                echo ""
                echo ""
                echo "user '$var_username' already exists"
                #exit 1
        else
                pass=$(perl -e 'print crypt($ARGV[0], "password")' $var_password)
                useradd -ou 0 -g 0 -p $pass $var_username
                echo ""
                [ $? -eq 0 ] && echo "User has been added to system!" || echo "Failed to add a user!"
                echo ""
        fi
    else
        echo "Skip ..."
    fi
fi

echo ""
echo "Installation done"
echo ""
