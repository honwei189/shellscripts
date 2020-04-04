#!/bin/bash

if [ ! -d "./bin" ]; then
  mkdir ./bin
fi

for file in $(find . -type f -name "*.sh" ! -name "install.sh")
do
  name=`basename "${file%.*}"`
  #shc -v -r -f $file
  shc -f $file
  mv $file.x bin/
  mv $file.x.c bin/
  gcc -o bin/$name bin/$file.x.c
  chmod 700 bin/$name
  mv bin/$name /usr/bin/$name
  #rm -rf /usr/bin/$name
done

rm -rf bin/*.x.c
rm -rf bin/*.x

crontab -l | { cat; echo "0 0 * * * /usr/bin/backup >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "0 0 * * * /usr/bin/bak_nginx_logs >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "*/5 * * * * /usr/bin/block_web_attack /var/log/nginx >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "0 4 * * 0 /usr/bin/cloudflare-update >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "0 0 * * * /usr/sbin/tmpwatch -am 24 /tmp >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "#0 0 * * * /usr/sbin/tmpwatch -am 168 /var/lib/php/session >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "#0 0 * * * /usr/sbin/tmpwatch -am 24 /data/tmp >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "0 0 * * * /usr/bin/vacumn_nginx_logs >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "* * * * * find /data/tmp -amin +5 -size 0 -delete >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "* * * * * find /var/lib/php/session -amin +5 -size 0 -delete >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "0 0 * * 0 yum update -y >/dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "0 0 * * 2,4,6 yum clean all >/dev/null 2>&1 && yum makecache fast >/dev/null 2>&1"; } | crontab -

