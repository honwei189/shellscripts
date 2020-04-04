#!/bin/sh

BACKUP_PATH="/data/backup"
BACKUP_STORE_PATH="/mnt/storage"
MYSQL_PATH="$BACKUP_PATH/mysql"

BACKUP_DIR="/apps
/root/
/etc/"

SERVER=`hostname`
SCRIPT="DAILY BACKUP"
EMAIL="YOUR_EMAIL"
EMAIL_HEADERS="From: $EMAIL\r\nX-Mailer: None\r\nMIME-Version: 1.0\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n";
DAY="$(date +%u)"
MyUSER="root"
MyPASS=""
MyHOST="localhost"

MYSQL="$(which mysql)"
MYSQLDUMP="$(which mysqldump)"
CHOWN="$(which chown)"
CHMOD="$(which chmod)"
GZIP="$(which gzip)"

CUR_DAY=`date +%a`
DAY="$(date +%u)"
NOW="$(date +"%Y%m%d")"

# File to store current backup file
FILE=""
# Store list of databases
DBS=""

# DO NOT BACKUP these databases
IGGY="
information_schema
performance_schema
mysql
test
"

archives(){
  $(which) 7z a -mx0 "$BACKUP_PATH/bak.$DAY.7z" $BACKUP_PATH/*

  result=""
  result=$(if $(which) 7z t "$BACKUP_PATH/bak.$DAY.7z" 2>&1 > /dev/null; then echo passed; else echo failed; fi)

  check="";

  if [ "$result" == "passed" ];
  then
    if [ ! -d "$BACKUP_STORE_PATH" ]; then
      mkdir -p $BACKUP_STORE_PATH
    fi

    mv "$BACKUP_PATH/bak.$DAY.7z" $BACKUP_STORE_PATH;
  else
php << EOF
    <?php
      mail("$EMAIL", "[$SERVER] [$SCRIPT] Backup has FAILED on ".date("Y-m-d h:i A"), "$result", "$EMAIL_HEADERS");
    ?>
EOF
  fi
}

files(){
  for dir in $BACKUP_DIR;
  do
    cp -Rpu --parents $dir $BACKUP_PATH/root/
  done

  mv $BACKUP_PATH/root/etc/fstab $BACKUP_PATH/root/etc/fstab.bak
  mv $BACKUP_PATH/root/etc/sysconfig $BACKUP_PATH/root/etc/sysconfig.bak
}

mysql(){
  [ ! -d $MYSQL_PATH ] && mkdir -p $MYSQL_PATH || :

  # Only root can access it!
  #$CHOWN 0.0 -R $DEST
  #$CHMOD 0600 $DEST

  # Get all database list first
  if [ "$MyPASS" == "" ]; then
    DBS="$($MYSQL -u $MyUSER -h $MyHOST -Bse 'show databases')"
  else
    DBS="$($MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -Bse 'show databases')"
  fi

  for db in $DBS
  do
    skipdb=-1
    if [ "$IGGY" != "" ];
    then
        for i in $IGGY
        do
            [ "$db" == "$i" ] && skipdb=1 || :
        done
    fi

    if [ "$skipdb" == "-1" ] ; then
        find $MYSQL_PATH -name "$db*.$DAY.7z" -exec rm -rf {} \;

        #FILE="$MYSQL_PATH/$db.$NOW.gz"
        FILE="$MYSQL_PATH/$db.$NOW.7z"

        if [ "$MyPASS" == "" ]; then
          #$MYSQLDUMP -u $MyUSER -h $MyHOST $db | $GZIP -9 > $FILE
          #$MYSQLDUMP -u $MyUSER -h $MyHOST $db | 7z a -si -txz -mx=9 -mmt=on $FILE
          $MYSQLDUMP -u $MyUSER -h $MyHOST $db | $(which) 7z a -si $FILE
        else
          #$MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db | $GZIP -9 > $FILE
          #$MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db | 7z a -si -txz -mx=9 -mmt=on $FILE
          $MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db | $(which) 7z a -si $FILE
        fi
    fi
  done
}

rm -rf $BACKUP_PATH/*.7z
rm -rf $BACKUP_PATH/root/*
rm -rf $BACKUP_PATH/mysql/*

if [ ! -d "$BACKUP_PATH/root/" ]; then
  mkdir -p $BACKUP_PATH/root/
fi

if [ ! -d "$BACKUP_PATH/mysql/" ]; then
  mkdir -p $BACKUP_PATH/mysql/
fi

mysql
files
archives

