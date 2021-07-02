#!/bin/sh
###
# @description       : Allows to get latest files from GIT and allows to skip update certains file
# @usage             : update
# @version           : "1.1.1"
# @creator           : Gordon Lim <honwei189@gmail.com>
# @created           : 12/05/2020 16:06:05
# @last modified     : 01/07/2021 08:29:31
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
# Go to your git folder (the folder execute "git clone" before), type "update"
# and press enter
#
###############################################################################

pwd=$(pwd)

SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

check_git_dir() {
    if [[ -d $pwd/.git ]] && [[ -f $pwd/.git/config ]]; then
        # LAST_UPDATE=`git show --no-notes --format=format:"%H" | head -n 1`
        # LAST_COMMIT=`git show --no-notes --format=format:"%H" | head -n 1`
        LAST_UPDATE=$(git rev-parse HEAD)
        LAST_COMMIT=$(git ls-remote $(git rev-parse --abbrev-ref @{u} | sed 's/\// /g') | cut -f1)
        LAST_UPDATE_DATE_TIME=$(git for-each-ref --format='%(committerdate)' --sort='-committerdate' --count 1)
        LAST_UPDATE_DATE_ONLY=$(echo "$LAST_UPDATE_DATE_TIME" | sed 's/+.*$//g' | xargs -I{} date -d {} +"%Y-%m-%d")
        LAST_UPDATE_DATE_TIME=$(echo "$LAST_UPDATE_DATE_TIME" | sed 's/+.*$//g' | xargs -I{} date -d {} +"%d/%m/%Y %H:%M:%S")
        TODAY=$(date +"%Y-%m-%d")

        #Store userid passsword for 1 min
        git config credential.helper store
        git config credential.helper 'cache --timeout=60'
    else
        echo ""
        $SETCOLOR_FAILURE
        echo -en "Unable to update files from GIT repository, because of "
        $SETCOLOR_SUCCESS
        echo -en $pwd
        $SETCOLOR_FAILURE
        echo -en " is not a git repository directory"
        $SETCOLOR_NORMAL
        echo ""
        echo ""
        exit 1
    fi

    # UPSTREAM=${1:-'@{u}'}
    # LOCAL=$(git rev-parse @)
    # REMOTE=$(git rev-parse "$UPSTREAM")
    # BASE=$(git merge-base @ "$UPSTREAM")

    # [ $(git rev-parse HEAD) = $(git ls-remote $(git rev-parse --abbrev-ref @{u} | \
    # sed 's/\// /g') | cut -f1) ] && echo up to date || echo not up to date

    # if [ $LOCAL = $REMOTE ]; then
    #     echo "Up-to-date"
    # elif [ $LOCAL = $BASE ]; then
    #     echo "Need to pull"
    # elif [ $REMOTE = $BASE ]; then
    #     echo "Need to push"
    # else
    #     echo "Diverged"
    # fi
}

changelog() {
    if [ "$1" == "" ]; then
        DATE=$LAST_UPDATE_DATE_ONLY
    else
        DATE=$1
    fi

    echo ""
    echo ""
    $SETCOLOR_SUCCESS
    echo -en "Changelog [ Since "
    $SETCOLOR_FAILURE
    echo -en $DATE
    $SETCOLOR_SUCCESS
    echo -en " ] :"
    echo ""
    echo "----------------------------------------------------------------"
    $SETCOLOR_NORMAL
    git log --pretty="format:%B" --abbrev-commit --date=relative origin/master master --since="$DATE 12am" | sed '/^$/d' | sed '$!N; /^\(.*\)\n\1$/!P; D' | awk '{print NR  ". " $s}'

    echo ""
}

update() {
    if [ $LAST_COMMIT != $LAST_UPDATE ]; then
        if [[ -f $pwd/.ignores ]]; then
            #git ls-files -v | grep '^h' | sed 's/^..//' | sed 's/\ /\\ /g' | xargs -I FILE git update-index --no-assume-unchanged FILE || true
            git ls-files -v | grep '^h' | sed 's/^..//' | sed 's/\ /\\ /g' | xargs -I FILE git update-index --no-assume-unchanged FILE

            # for list in $(cat $pwd/.ignores | awk '/^;/{next}1' | awk '/^#/{next}1'); do
            for list in $(cat $pwd/.ignores | egrep -v '^(;|#|//|$)'); do
                #find $dir -print0 | ls {} \;
                list="$(echo -e "${list}" | sed -e 's/^[[:space:]]*//')"

                if [[ $list == *"*"* ]]; then
                    list=$(echo $list | sed -e "s/\*//g" | tr -d '\r')
                    #echo $list
                    #find $list -maxdepth 1 -type d \( ! -name . \) -exec bash -c "cd '{}' && pwd && git ls-files -z ${pwd} | xargs -0 git update-index --assume-unchanged" \;

                    if [[ -f $list ] || [ -d $list ] ]; then
                        for f in $(find $list -type f \( ! -name . \)); do
                            if [[ -d $f ]]; then
                                git update-index --assume-unchanged "$f" >/dev/null 2>&1
                            fi
                        done
                    fi
                else
                    if [[ -d $list ]]; then
                        git update-index --assume-unchanged "$list/" >/dev/null 2>&1
                    fi

                    if [[ -f $list ]]; then
                        git update-index --assume-unchanged "$list" >/dev/null 2>&1
                    fi
                fi
            done

            # git update-index --assume-unchanged $pwd/.ignores >/dev/null 2>&1
        else
            touch $pwd/.ignores
            echo "# To skip update following files / folders from GIT" >>$pwd/.ignores
            echo "# " >>$pwd/.ignores
            echo "# Example:" >>$pwd/.ignores
            echo "# " >>$pwd/.ignores
            echo "# abc.txt" >>$pwd/.ignores
            echo "# def/*" >>$pwd/.ignores
            echo "# example" >>$pwd/.ignores
            echo "# tests/js" >>$pwd/.ignores
            echo "# " >>$pwd/.ignores
        fi

        #echo "Fetch branches"
        #echo ""

        echo ""
        $SETCOLOR_SUCCESS
        #echo "[ Refresh update list from $(git remote get-url $(git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD)|cut -d/ -f1)) ]"
        echo "[ Refresh update list from $(git config --get remote.origin.url) ]"
        echo "----------------------------------------------------------------------------------------------"
        $SETCOLOR_FAILURE
        echo "Completed"
        $SETCOLOR_NORMAL
        echo ""
        echo ""
        
        git fetch >/dev/null 2>&1

        $SETCOLOR_SUCCESS
        echo "[ Start updating ... ]"
        $SETCOLOR_NORMAL
        echo ""

        #for file in $(git diff master origin/master --name-only); do
        #for file in $(git diff --name-only | tr -d '\n'); do
        ##for file in $(git diff --name-only); do
        #    git checkout "$file" >/dev/null
        #done


        for file in $(git diff --name-only $(git rev-parse HEAD) $(git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD) | tr -d "\n")); do
            # if [ $(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' | grep "$file") == "$file" ]; then
            if [ $(git config --file .gitmodules --get-regexp path | awk '{ print $2 }') == "$file" ]; then
                cd $file
                git fetch >/dev/null 2>&1

                #for files in $(git diff --name-only $(git rev-parse HEAD) origin/master); do
                #    #echo "git checkout \"$files\"";
                #    git checkout $files
                #done

                remote=$(git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD) | tr -d "\n")

                #git diff --name-only $(git rev-parse HEAD) $remote | xargs -I FILE git checkout FILE

                for files in $(git diff --name-only $(git rev-parse HEAD) $remote); do
                    #echo "git checkout \"$files\"";
                    if [[ -f $files ]]; then
                        git checkout "$files"
                    fi
                done

                git pull $(echo $remote | sed 's/\// /g')

                cd $pwd
            else
                git checkout "$file"
                #echo "git checkout \"$file\"";
            fi
        done

        #echo "Prepare to update submodule"
        #echo ""
        #echo ""

        #if [[ -f $pwd/.gitmodules ]]; then
        #    #git submodule update --recursive >/dev/null 2>&1
        #    git submodule foreach git pull origin master
        #fi

        git pull

        if [[ ! "$TODAY" == "$LAST_UPDATE_DATE_ONLY" ]]; then
            LAST_UPDATE_DATE_ONLY=$TODAY
        fi

        changelog
    else
        # echo "No updates available"
        echo ""
        $SETCOLOR_SUCCESS
        echo "Already up-to-date."
        $SETCOLOR_NORMAL
        echo ""
        exit 1
    fi
}

help() {
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ Update files from GIT ]"
    $SETCOLOR_NORMAL
    echo ""

    $SETCOLOR_FAILURE
    echo "Usage : "
    echo ""
    echo -n "$0 "
    $SETCOLOR_SUCCESS
    echo "{log}"

    echo ""
    echo -e " \t\t- Execute \"$0\" to update files from GIT repository.  e.g: sh $0"
    echo -e "log \t\t- Get latest changelog.  You can get changelog since from specific date"

    echo ""
    echo ""
    $SETCOLOR_FAILURE
    echo "Example : "
    echo ""
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " log "
    $SETCOLOR_NORMAL
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " log "
    $SETCOLOR_NORMAL
    echo "2020-05-20"
    echo ""
}

#clear

case "$1" in
log)
    check_git_dir
    changelog $2
    ;;
-h)
    help
    ;;
-help)
    help
    ;;
--help)
    help
    ;;
*)
    check_git_dir
    update
    ;;
esac

exit 0
