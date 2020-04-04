#!/bin/bash

if [ ! "$1" ] ; then
  echo $"Usage: $0 FILE_NAME"
  exit
fi

if [ ! -d "./bin" ]; then
  mkdir ./bin
fi

file=$1
name=`basename "${file%.*}"`
#shc -v -r -f $file
shc -f $file
mv $file.x bin/
mv $file.x.c bin/
gcc -o bin/$name bin/$file.x.c
chmod 700 bin/$name
mv bin/$name /usr/bin/$name
#rm -rf /usr/bin/$name

rm -rf bin/*.x.c
rm -rf bin/*.x

