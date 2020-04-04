#!/bin/bash

FILES=$(find /var/log/nginx -type f -name '*.log')
DATE="$(date -d "yesterday" +"%Y%m%d")"

if [ ! -d "/var/log/nginx/bak" ]; then
  mkdir -p /var/log/nginx/bak
fi

if [ ! -d "/var/log/nginx/bak/default" ]; then
  mkdir -p /var/log/nginx/bak/default
fi

mv /var/log/nginx/*.gz /var/log/nginx/bak/default/

for file in $FILES
do
  FILESIZE=$(stat -c%s "$file")
  if [ $FILESIZE -gt 0 ]; then
    name=$(basename $file)
    #dir=$(basename $(dirname $(dirname $file)))
    dir=$(echo $file |awk -F'/' '$0=$(NF-1)')
    if [ "$dir" == "nginx" ]; then
      dir="";
    else
      dir="$dir/";
    fi

    if [ ! -d "/var/log/nginx/bak/$dir" ]; then
      mkdir -p /var/log/nginx/bak/$dir
    fi

    /usr/local/bin/7z a /var/log/nginx/bak/$dir$name.$DATE.7z $file && cat /dev/null > $file
  fi

done
