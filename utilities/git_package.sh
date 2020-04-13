#!/bin/sh
#Usage : sh package.sh 2020-01-01
###
 # @description       : Packaging updates from GIT for Linux platform
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 13/04/2020 09:36:41
 # @last modified     : 13/04/2020 09:40:30
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###

#git diff --name-only origin/master master > ../list.txt

if [ ! -d "../git_changed_files" ]; then
    mkdir -p ../git_changed_files
else
   rm -rf ../git_changed_files/*
fi

git pull
git log --pretty="format:" --name-only --after="$1" | sort | uniq > ../git_changed_files/list.txt
#git log --pretty="format:%<(20)  - %B" --abbrev-commit --date=relative origin/master master --after="$1" > ../git_changed_files/changelog.txt

git log --pretty="format:%B" --abbrev-commit --date=relative origin/master master --after=$1 | sed '/^$/d' | sed '$!N; /^\(.*\)\n\1$/!P; D' > log.txt
cat log.txt | awk '{print NR  ". " $s}' > ../git_changed_files/changelog.txt
rm -rf log.txt


(cat ../git_changed_files/list.txt) | while read file
do
  if [ ! -z "$file" ]
  then
    if [ -f "$file" ] || [ -d "$file" ]; then
        cp -Rpu --parents $file ../git_changed_files/
    fi
  fi
done

rm -rf ../git_changed_files/list.txt
7z a ../git_changed_files/update.7z ../git_changed_files/*
