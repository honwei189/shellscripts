#!/bin/sh
###
 # @description       : Update files from GIT
 # @usage             : update
 # @version           : "1.0.0"
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 12/05/2020 16:06:05
 # @last modified     : 13/05/2020 14:54:25
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
###

 ################################# INSTALLATION ################################
 # Make sure that "/usr/bin/update" doesn't exist
 #
 # ln -s update-from-git.sh /usr/bin/update
 # or;
 # mv update-from-git.sh /usr/bin/update
 #
 # chmod +x /usr/bin/update
 #
 # Go to your git folder (the folder execute "git clone" before), type "enter"
 # and press enter
 #
 ###############################################################################

pwd=$(pwd)

if [[ -f $pwd/.ignores ]]; then
    # for list in $(cat $pwd/.ignores | awk '/^;/{next}1' | awk '/^#/{next}1'); do
    for list in $(cat $pwd/.ignores | egrep -v '^(;|#|//|$)'); do
        #find $dir -print0 | ls {} \;
        list="$(echo -e "${list}" | sed -e 's/^[[:space:]]*//')"

        if [[ $list == *"*"* ]]; then
            list=$(echo $list | sed -e "s/\*//g")
            #echo $list
            #find $list -maxdepth 1 -type d \( ! -name . \) -exec bash -c "cd '{}' && pwd && git ls-files -z ${pwd} | xargs -0 git update-index --assume-unchanged" \;
            for f in $(find $list -type f \( ! -name . \)); do
                git update-index --assume-unchanged $list >/dev/null 2>&1
            done
        else
            if [[ -d $list ]]; then
                git update-index --assume-unchanged $list/ >/dev/null 2>&1
            fi

            if [[ -f $list ]]; then
                git update-index --assume-unchanged $list >/dev/null 2>&1
            fi
        fi
    done

    # git update-index --assume-unchanged $pwd/.ignores >/dev/null 2>&1
else
    touch $pwd/.ignores
    echo "# To skip update following files / folders from GIT" >> $pwd/.ignores
    echo "# " >> $pwd/.ignores
    echo "# Example:" >> $pwd/.ignores
    echo "# " >> $pwd/.ignores
    echo "# abc.txt" >> $pwd/.ignores
    echo "# def/*" >> $pwd/.ignores
    echo "# example" >> $pwd/.ignores
    echo "# tests/js" >> $pwd/.ignores
    echo "# " >> $pwd/.ignores
fi

git pull
