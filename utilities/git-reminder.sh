#!/bin/sh
###
 # @description       : Add GIT project URL and email address to register reminder notifications
 # @requires          : phpmailer (can get a ready copy from https://github.com/honwei189/shellscripts/tree/master/utilities/phpmailer)
 #                      composer (can get it from https://getcomposer.org/)
 # @usage             : git-reminder add GIT_URL EMAIL_ADDRESS
 #                      git-reminder check
 #                      git-reminder check GIT_URL
 #                      git-reminder check GIT_URL EMAIL_ADDRESS
 #                      git-reminder del GIT_URL
 #                      git-reminder del GIT_URL EMAIL_ADDRESS
 #                      git-reminder delete GIT_URL
 #                      git-reminder delete GIT_URL EMAIL_ADDRESS
 #                      git-reminder list
 #                      git-reminder list GIT_URL
 #                      git-reminder search EMAIL_ADDRESS
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 29/04/2020 15:53:09
 # @last modified     : 30/04/2020 16:46:30
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###

 ################################# INSTALLATION ################################
 # ln -s git-reminder.sh /usr/bin/git-reminder
 # or;
 # mv git-reminder.sh /usr/bin/git-reminder
 #
 # chmod +x /usr/bin/git-reminder
 #
 # crontab (automatically run hourly):  0 8 * * * /usr/bin/GIT-reminder check >/dev/null 2>&1
 #
 #
 # mkdir -p /usr/local/src/ && \
 # pushd "`cd /usr/local/src/ && composer require phpmailer/phpmailer`" && popd && \
 # curl -L https://github.com/honwei189/shellscripts/raw/master/utilities/phpmailer/send.php \
 # -o /usr/local/src/phpmailer/send.php
 #
 # vi /usr/local/src/phpmailer/send.php
 #
 ###############################################################################


SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"


################################################################
# (DO NOT CHANGE)
################################################################

GIT_REMINDER_PATH="/etc/gitreminder"
GIT="$GIT_REMINDER_PATH/git"
EMAIL_LIST="$GIT_REMINDER_PATH/email"


if [ -f $GIT_REMINDER_PATH/reminder.conf ]; then
    . $GIT_REMINDER_PATH/reminder.conf
else
    echo ""
    echo -en "Please edit "
    $SETCOLOR_NORMAL
    $SETCOLOR_FAILURE
    echo -en "/etc/gitreminder/reminder.conf"
    $SETCOLOR_SUCCESS
    echo -en " before execute."
    echo ""
    echo ""
    echo "After done, please run this command again"
    $SETCOLOR_NORMAL
    echo ""
    echo ""


    touch /etc/gitreminder/reminder.conf
    echo "GIT_USER=GIT_USER_ID" >> /etc/gitreminder/reminder.conf
    echo "GIT_PASSWORD=GIT_PASSWORD" >> /etc/gitreminder/reminder.conf
    echo "" >> /etc/gitreminder/reminder.conf
    echo "################################################################" >> /etc/gitreminder/reminder.conf
    echo "# CC REMINDER EMAIL.  USE ; IF MORE THAN ONE.  " >> /etc/gitreminder/reminder.conf
    echo "# e.g:  abc@email.com;cde@email.com" >> /etc/gitreminder/reminder.conf
    echo "################################################################" >> /etc/gitreminder/reminder.conf
    echo "EMAIL_CC=" >> /etc/gitreminder/reminder.conf
    echo "" >> /etc/gitreminder/reminder.conf
    echo "" >> /etc/gitreminder/reminder.conf
    echo "################################################################" >> /etc/gitreminder/reminder.conf
    echo "# SEND REMINDER IF MORE THAN HOW MANY DAYS NOT PUSH TO GIT" >> /etc/gitreminder/reminder.conf
    echo "################################################################" >> /etc/gitreminder/reminder.conf
    echo "days=7" >> /etc/gitreminder/reminder.conf
    echo "" >> /etc/gitreminder/reminder.conf
    echo "" >> /etc/gitreminder/reminder.conf

    exit 1
fi

#SENDER_EMAIL="no-reply@doxapps.com"

##########

#EMAIL_HEADERS="From: $SENDER_EMAIL\r\nBCC: $EMAIL_CC\r\nX-Mailer: None\r\nMIME-Version: 1.0\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n";

if [ -z ${GIT_USER} ]; then
    GIT_USER=
fi

if [ -z ${GIT_PASSWORD} ]; then
    GIT_PASSWORD=
fi

if [ -z ${EMAIL_CC} ]; then
    EMAIL_CC=
fi

if [ -z ${days} ]; then
    days=7
fi

if [ ! -d $GIT_REMINDER_PATH ]; then
    mkdir -p $GIT_REMINDER_PATH
fi

if [ ! -f $GIT ]; then
    touch $GIT
fi

if [ ! -f $EMAIL_LIST ]; then
    touch $EMAIL_LIST
fi

add(){
    if [ "$1" == "" ];then
        help
        exit 1
    fi

    if [ "$2" == "" ];then
        help
        exit 1
    fi

    find=$(cat $GIT | grep "$1")
    if [ "$find" == "" ]; then
        echo "$1" >>$GIT
        echo "$1:$2" >>$EMAIL_LIST
    else
        find=$(cat $EMAIL_LIST | grep "$1:$2")
        if [ "$find" == "" ]; then
            echo "$1:$2" >>$EMAIL_LIST
        else
            echo ""

            echo -n "Email "
            $SETCOLOR_FAILURE
            echo -n "$2"
            $SETCOLOR_SUCCESS
            echo " already exists"
            $SETCOLOR_NORMAL
            echo ""
            echo ""
        fi
    fi
}

check(){
    fromdate=$(date +"%Y-%m-%d" --date="$days days ago")
    todate=$(date +"%Y-%m-%d")
    today=$(date +"%d/%m/%Y")
    pwd="$GIT_USER:$GIT_PASSWORD@"

    if [ ! "$1" == "" ];then
        git_ls=$(cat $GIT | grep "$1")
    else
        git_ls=$(cat $GIT)
    fi
    
    for GITproj in $git_ls; do
        tmpdir=`mktemp -d /tmp/GIT-tmp.XXXXXX` >/dev/null 2>&1 || exit 1

        GIT_url=$(echo $GITproj | sed -e "s/:\/\//:\/\/${pwd}/g")
        
        pushd "$tmpdir" >/dev/null 2>&1 || exit 1
        git clone --depth=1 -n "$GIT_url" .  >/dev/null 2>&1
        log=$(git log --after=$fromdate --until=$todate)
        lastupdate=$(git log -1 --format="%at" | xargs -I{} date -d @{} +"%d/%m/%Y %H:%M:%S")
        popd >/dev/null 2>&1

        rm -rf "$tmpdir"

        if [ "$log" == "" ]; then
            for emailhost in $(cat $EMAIL_LIST | grep "$GITproj:"); do
                email=$(echo $emailhost | cut -d":" -f3)

                if [ ! "$email" == "" ]; then
                    if [ ! "$lastupdate" == "" ]; then
                        date_str="The last update date is on $lastupdate"
                    else
                        date_str="However, the project is never updated"
                    fi

                    from=$(echo $lastupdate | cut -d" " -f1)
                    from=`echo $from | awk  -F\/ '{print $3$2$1}'`
                    to=`echo $today | awk  -F\/ '{print $3$2$1}'`

                    START_DATE=`date --date=$from +"%s"`
                    END_DATE=`date --date=$to +"%s"`

                    DAYS=$((($END_DATE - $START_DATE) / 86400 ))
                    
                    msg="Dear $email,<br><br>$GITproj<br><br>The project has over $DAYS days not updated, usually should update it within $days days.  $date_str .<br><br>Please PUSH your files to GIT immediately if you have modified source codes.<br><br>Thank you."

                    if [ ! "$2" == "" ]; then
                        if [ "$2" == "$email" ]; then
                            php /usr/local/lib/phpmailer/send.php $email "GIT reminder ($today) - $GITproj" "$msg" $EMAIL_CC
                        fi
                    else
                        php /usr/local/lib/phpmailer/send.php $email "GIT reminder ($today) - $GITproj" "$msg" $EMAIL_CC
                    fi
                    
                    # php << EOF
                    #     <?php
                    #       mail("$email", "GIT reminder (".date("d/m/Y"). ") - $GITproj", "$msg", "$EMAIL_HEADERS");
                    #     ?>
                    # EOF
                fi
            done
        fi
    done
}

delete(){
    if [ ! "$2" == "" ];then
        find=$(cat $EMAIL_LIST | grep "$1:$2")
        if [ ! "$find" == "" ]; then
            url=$(echo $1 | sed -e "s%/%\\\/%g")
            sed --in-place "/$url:$2/d" $EMAIL_LIST
        else
            echo ""

            echo -n "Email "
            $SETCOLOR_FAILURE
            echo -n "$2"
            $SETCOLOR_SUCCESS
            echo " is not exist"
            $SETCOLOR_NORMAL
            echo ""
            echo ""
        fi
    else
        if [ "$1" == "" ];then
            help
            exit 1
        else
            find=$(cat $EMAIL_LIST | grep "$1")
            if [ ! "$find" == "" ]; then
                url=$(echo $1 | sed -e "s%/%\\\/%g")
                sed --in-place "/$url/d" $EMAIL_LIST
            fi

            find=$(cat $GIT | grep "$1")
            if [ ! "$find" == "" ]; then
                url=$(echo $1 | sed -e "s%/%\\\/%g")
                sed --in-place "/$url/d" $GIT
            else
                echo ""

                echo -n "GIT "
                $SETCOLOR_FAILURE
                echo -n "$1"
                $SETCOLOR_SUCCESS
                echo " is not exist"
                $SETCOLOR_NORMAL
                echo ""
                echo ""
            fi
        fi
    fi
}

list(){
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ GIT reminder list ]"
    $SETCOLOR_NORMAL
    echo ""

    if [ "$1" == "" ];then
        for GITproj in $(cat $GIT); do
            $SETCOLOR_FAILURE
            echo "$GITproj :"

            for emailhost in $(cat $EMAIL_LIST | grep "$GITproj:"); do
                email=$(echo $emailhost | cut -d":" -f3)
                $SETCOLOR_NORMAL
                $SETCOLOR_SUCCESS
                echo -en " \t- $email"    
                $SETCOLOR_NORMAL
                echo ""
            done

            echo ""
            echo ""
        done
    else
        for emailhost in $(cat $EMAIL_LIST | grep "$1:"); do
            email=$(echo $emailhost | cut -d":" -f3)
            $SETCOLOR_NORMAL
            $SETCOLOR_SUCCESS
            echo -en " \t- $email"
            $SETCOLOR_NORMAL
            echo ""
        done

        echo ""
    fi
}

search(){
    if [ "$1" == "" ];then
        help
        exit 1
    fi

    echo ""
    $SETCOLOR_SUCCESS
    echo "[ Search email in reminder list]"
    $SETCOLOR_NORMAL
    echo ""

    $SETCOLOR_FAILURE
    echo "$1 :"

    for emailhost in $(cat $EMAIL_LIST | grep "$1"); do
        host=$(echo $emailhost | sed -e "s/:${1}//g")

        $SETCOLOR_NORMAL
        $SETCOLOR_SUCCESS
        echo -en " \t- $host"
        $SETCOLOR_NORMAL
        echo ""
    done

    echo ""
}

help() {
    echo ""
    $SETCOLOR_SUCCESS
    echo "[ Add GIT project into reminder list ]"
    $SETCOLOR_NORMAL
    echo ""

    $SETCOLOR_FAILURE
    echo "Usage : "
    echo ""
    echo -n "$0 "
    $SETCOLOR_SUCCESS
    echo "{add|check|del|delete|list|search}"

    echo ""
    echo -e "add \t\t- Add GIT project and register email address into reminder list"
    echo -e "check \t\t- Check GIT log and send reminder"
    echo -e "del \t\t- Delete GIT project and registered email address from reminder list"
    echo -e "delete \t\t- Delete GIT project and registered email address from reminder list"
    echo -e "list \t\t- List all registered GIT projects and email addresses"
    echo -e "search \t\t- Search email address in registered reminder list"

    echo ""
    echo ""
    $SETCOLOR_FAILURE
    echo "Example : "
    echo ""
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " add "
    $SETCOLOR_NORMAL
    echo "GIT_URL EMAIL_ADDRESS"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " delete "
    $SETCOLOR_NORMAL
    echo "GIT_URL"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " delete "
    $SETCOLOR_NORMAL
    echo "GIT_URL EMAIL_ADDRESS"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " search "
    $SETCOLOR_NORMAL
    echo "EMAIL_ADDRESS"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo " list"
    $SETCOLOR_NORMAL
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " list "
    $SETCOLOR_NORMAL
    echo "GIT_URL"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo " check"
    $SETCOLOR_NORMAL
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " check "
    $SETCOLOR_NORMAL
    echo "GIT_URL"
    echo ""
    $SETCOLOR_FAILURE
    echo -n "$0"
    $SETCOLOR_SUCCESS
    echo -n " check "
    $SETCOLOR_NORMAL
    echo "GIT_URL EMAIL_ADDRESS"
    echo ""
}

#clear

case "$1" in
add)
    add $2 $3
    ;;
check)
    check $2 $3
    ;;
del)
    delete $2 $3
    ;;
delete)
    delete $2 $3
    ;;
list)
    list $2 $3
    ;;
search)
    search $2
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
    help
    ;;
esac

exit 0
