#!/bin/bash

# Script for Automated MySQL and File Backups
# This script performs automated backups for MySQL databases and specified directories.
# It supports both full and incremental backups, along with optional email notifications.
# The script includes features for backup validation, compression, and remote cloning.
#
# Configuration:
# - BACKUP_PATH: Local backup directory
# - CLONE_PATH: Remote backup directory
# - FULL_BACKUP_PATH: Directory for full backups
# - INCREMENTAL_BACKUP_PATH: Directory for incremental backups
# - BINLOG_BACKUP_PATH: Directory for MySQL binary log backups
# - MYSQL_PATH: Directory for MySQL backups
# - BACKUP_DIRS: Directories to backup
# - SERVER: Server hostname
# - EMAIL: Recipient email for notifications
# - WEEK_DAY: Current day of the week (1-7)
# - SENDER_NAME: Sender name for email notifications
# - DEFAULT_MAIL_TOOL: Mail tool for sending notifications (optional)
# - FULL_BACKUP_PREFIX: Prefix for full backup files
# - INCREMENTAL_BACKUP_PREFIX: Prefix for incremental backup files
# - BINLOG_BACKUP_PREFIX: Prefix for binlog backup files
# - FULL_BACKUP_DAY: Day for full backups (1-7)
# - INCREMENTAL_BACKUP_DAYS: Days for incremental backups (array, 1-7)
# - RETAIN_ALL_BACKUPS: Option to retain all backups (0 or 1)
# - CLONE_TO_BACKUP_SERVER: Option to clone backups to a remote server (0 or 1)
# - KEEP_LOCAL_BACKUP: Option to retain local backups after cloning (0 or 1)
# - SHOW_PROGRESS: Option to display progress during backups (0 or 1)
# - ARCHIVE_DIRECTLY_TO_SERVER: Option to compress directly to the server (0 or 1)
# - AUTO_GENERATE_DB_BACKUP_IF_NOT_FOUND: Option to auto-generate DB backup if not found (0 or 1)
# - INCREMENTAL_DB_BACKUP_METHOD: Method for incremental DB backups (0 for binlog, 1 for full dump)
# - VERIFY: Option to verify backups (0 or 1)
# - MyUSER: MySQL username
# - MyPASS: MySQL password
# - MyHOST: MySQL hostname
# - MYSQL, MYSQLDUMP, MYSQLBINLOG, GZIP, SYSTEMCTL, PV: Paths to required utilities
# - SEVENZIP: Path to 7z utility
# - IGNORE_DB: Databases to ignore during backup

# Configuration
BACKUP_PATH="/data/backup"
CLONE_PATH="/nfs/nas"
FULL_BACKUP_PATH="$BACKUP_PATH/full_backup"
INCREMENTAL_BACKUP_PATH="$BACKUP_PATH/incremental"
BINLOG_BACKUP_PATH="$BACKUP_PATH/mysql_incremental"
MYSQL_PATH="$BACKUP_PATH/mysql"
BACKUP_DIRS="/apps /etc"
SERVER=$(hostname)
EMAIL="RECIPIENT_EMAIL"
WEEK_DAY=$(date +%u)
SENDER_NAME="Server Backup <backup@$SERVER>"

DEFAULT_MAIL_TOOL=""

FULL_BACKUP_PREFIX="weekly_backup"
INCREMENTAL_BACKUP_PREFIX="daily_backup"
BINLOG_BACKUP_PREFIX="daily_backup"

FULL_BACKUP_DAY=7

INCREMENTAL_BACKUP_DAYS=(1 2 3 4 5 6)

RETAIN_ALL_BACKUPS=0
CLONE_TO_BACKUP_SERVER=1
KEEP_LOCAL_BACKUP=0
SHOW_PROGRESS=1
ARCHIVE_DIRECTLY_TO_SERVER=1
AUTO_GENERATE_DB_BACKUP_IF_NOT_FOUND=1
INCREMENTAL_DB_BACKUP_METHOD=0
VERIFY=0

MyUSER="root"
MyPASS=""
MyHOST="localhost"
MYSQL=$(which mysql)
MYSQLDUMP=$(which mysqldump)
MYSQLBINLOG=$(which mysqlbinlog)
GZIP=$(which gzip)
SYSTEMCTL=$(which systemctl)
PV=$(which pv)
SEVENZIP="/usr/bin/7z"

IGNORE_DB="information_schema performance_schema mysql test backup_test_db"


# Create necessary directories
mkdir -p $INCREMENTAL_BACKUP_PATH
mkdir -p $FULL_BACKUP_PATH
mkdir -p $MYSQL_PATH
mkdir -p $BINLOG_BACKUP_PATH
mkdir -p $CLONE_PATH
mkdir -p "$CLONE_PATH/mysql"

### Utility Functions ###

# Clone backup to remote server
clone_to_backup_server() {
    local source_path=$1
    local dest_path=$2

    echo "Cloning $source_path to $dest_path"

    if [[ "$dest_path" =~ .*@.*:.* ]]; then
        echo "Destination is a remote path. Using scp or rsync."
        ssh "${dest_path%@*}" "mkdir -p ${dest_path#*:}"
        rsync -avz "$source_path" "$dest_path"
    else
        echo "Destination is a local path. Ensuring directory exists."
        mkdir -p "$dest_path"
        rsync -av "$source_path" "$dest_path"
    fi

    if [ $? -ne 0 ]; then
        local message="Cloning $source_path to $dest_path failed"
        send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
        return 1
    fi
}

# Check storage space
check_storage() {
    local required_space_kb=$(convert_to_kb "$1")
    local available_space_kb=$(df "$BACKUP_PATH" | tail -1 | awk '{print $4}')

    if [ "$available_space_kb" -lt "$required_space_kb" ]; then
        local available_space_hr=$(convert_from_kb "$available_space_kb")
        local required_space_hr=$(convert_from_kb "$required_space_kb")
        local message="Backup failed: Not enough space\nAvailable: $available_space_hr\nRequired: $required_space_hr"
        echo -e "$message"
        send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
        exit 1
    fi
}

# Convert KB to human-readable storage units
convert_from_kb() {
    local size_kb=$1
    if [ $size_kb -lt 1024 ]; then
        echo "${size_kb} KB"
    elif [ $size_kb -lt $((1024 * 1024)) ]; then
        echo "$(echo "scale=2; $size_kb / 1024" | bc) MB"
    elif [ $size_kb -lt $((1024 * 1024 * 1024)) ]; then
        echo "$(echo "scale=2; $size_kb / (1024 * 1024)" | bc) GB"
    else
        echo "$(echo "scale=2; $size_kb / (1024 * 1024 * 1024)" | bc) TB"
    fi
}

# Convert human-readable storage units to KB
convert_to_kb() {
    local size=$1
    local unit=${size: -2}
    local value=${size%${unit}}

    case $unit in
    KB | kb) echo "$value" ;;
    MB | mb) echo "$((value * 1024))" ;;
    GB | gb) echo "$((value * 1024 * 1024))" ;;
    TB | tb) echo "$((value * 1024 * 1024 * 1024))" ;;
    *)
        echo "Invalid unit"
        exit 1
        ;;
    esac
}

# Extract and filter SQL from binlog files
extract_and_filter_sql() {
    local binlog_file=$1
    local db_name=$2
    local sql_file=$3

    $MYSQLBINLOG $binlog_file | awk -v db="$db_name" '
    BEGIN { in_db = 0; }
    {
        if ($0 ~ /Table_map: `/) {
            if ($0 ~ db) {
                in_db = 1;
            } else {
                in_db = 0;
            }
        }
        if (in_db) {
            print $0;
        }
    }' >$sql_file
}

# Function to check and install required tools
install_required_tools() {
    local tools=("pv" "rsync" "7z")

    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            echo "$tool not found. Installing..."

            if command -v yum &> /dev/null; then
                sudo yum install -y $tool
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y $tool
            else
                echo "Neither yum nor dnf found. Cannot install $tool. Exiting."
                exit 1
            fi
        fi
    done

    # Ensure 7z is installed
    if [ ! -x "$SEVENZIP" ]; then
        echo "7z not found at $SEVENZIP"
        exit 1
    fi

    # Ensure pv is installed
    if [ ! -x "$PV" ]; then
        SHOW_PROGRESS=0
        echo "pv not found, progress display disabled"
    fi
}

# Check if current day is in incremental backup days
is_incremental_backup_day() {
    for day in "${INCREMENTAL_BACKUP_DAYS[@]}"; do
        if [ "$WEEK_DAY" -eq "$day" ]; then
            return 0
        fi
    done
    return 1
}

# Send email notifications
send_email() {
    local recipient="$1"
    local subject="$2"
    local body="$3"
    local sender_name="$4"

    local email_headers="To: $recipient\nSubject: $subject\nFrom: $sender_name\n"

    if [[ -n "$DEFAULT_MAIL_TOOL" ]] && command -v "$DEFAULT_MAIL_TOOL" &> /dev/null; then
        case "$DEFAULT_MAIL_TOOL" in
            mailx)
                echo -e "$body" | mailx -s "$subject" -r "$sender_name" "$recipient"
                return $?
                ;;
            sendmail)
                echo -e "$email_headers\n$body" | sendmail -t
                return $?
                ;;
            mutt)
                echo -e "$body" | mutt -s "$subject" -e "set from=$sender_name" -- "$recipient"
                return $?
                ;;
            ssmtp)
                echo -e "$email_headers\n$body" | ssmtp "$recipient"
                return $?
                ;;
        esac
    fi

    if command -v mailx &> /dev/null; then
        echo -e "$body" | mailx -s "$subject" -r "$sender_name" "$recipient"
        return $?
    fi

    if command -v sendmail &> /dev/null; then
        echo -e "$email_headers\n$body" | sendmail -t
        return $?
    fi

    if command -v mutt &> /dev/null; then
        echo -e "$body" | mutt -s "$subject" -e "set from=$sender_name" -- "$recipient"
        return $?
    fi

    if command -v ssmtp &> /dev/null; then
        echo -e "$email_headers\n$body" | ssmtp "$recipient"
        return $?
    fi

    echo "No email sending command found!"
    return 1
}

### Main Functions ###

# Perform full MySQL backup
full_backup_mysql() {
    local db_name=$1

    if [ -z "$db_name" ]; then
        echo "Starting full MySQL backups..."
        DBS="$($MYSQL -u $MyUSER -h $MyHOST -Bse 'show databases')"
        total_dbs=$(echo "$DBS" | wc -l)
        db_count=0
        for db in $DBS; do
            skipdb=0
            for ignore in $IGNORE_DB; do
                if [ "$db" == "$ignore" ]; then
                    skipdb=1
                    break
                fi
            done
            if [ "$skipdb" -eq 0 ]; then
                db_count=$((db_count + 1))
                echo "Backing up database ($db_count/$total_dbs): $db"
                backup_single_db $db
            fi
        done
    else
        backup_single_db $db_name
    fi
}

# Backup single database
backup_single_db() {
    local db=$1

    if [ $RETAIN_ALL_BACKUPS -eq 1 ]; then
        FILE="$MYSQL_PATH/$db.$(date +%Y%m%d).sql"
    else
        FILE="$MYSQL_PATH/$db.sql"
    fi

    if [ -z "$MyPASS" ]; then
        if [ $SHOW_PROGRESS -eq 1 ]; then
            $MYSQLDUMP -u $MyUSER -h $MyHOST $db --single-transaction --quick | $PV >$FILE
        else
            $MYSQLDUMP -u $MyUSER -h $MyHOST $db --single-transaction --quick >$FILE
        fi
    else
        if [ $SHOW_PROGRESS -eq 1 ]; then
            $MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db --single-transaction --quick | $PV >$FILE
        else
            $MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db --single-transaction --quick >$FILE
        fi
    fi

    if [ $? -ne 0 ]; then
        local message="MySQL full backup failed for database $db"
        send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
        return 1
    fi

    echo "Compressing full backup for database: $db"
    if [ $SHOW_PROGRESS -eq 1 ]; then
        $PV "$FILE" | $SEVENZIP a -si -mx0 "$FILE.7z"
    else
        $SEVENZIP a -mx0 "$FILE.7z" "$FILE"
    fi
    if [ $? -ne 0 ]; then
        local message="7z compression failed for database $db"
        send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
        return 1
    fi

    rm "$FILE" 

    if [ $VERIFY -eq 1 ]; then
        echo "Verifying full backup for database: $db"
        if [ -z "$MyPASS" ]; then
            $SEVENZIP e -so "$FILE.7z" | $MYSQL -u $MyUSER -h $MyHOST -e "CREATE DATABASE IF NOT EXISTS backup_test_db; USE backup_test_db; SOURCE /dev/stdin;"
        else
            $SEVENZIP e -so "$FILE.7z" | $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "CREATE DATABASE IF NOT EXISTS backup_test_db; USE backup_test_db; SOURCE /dev/stdin;"
        fi

        if [ $? -ne 0 ]; then
            local message="Validation of MySQL full backup failed for database $db"
            send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
            return 1
        fi
        $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE backup_test_db;"
    fi

    if [ $CLONE_TO_BACKUP_SERVER -eq 1 ]; then
        clone_to_backup_server "$FILE.7z" "${CLONE_PATH}/mysql/"
    fi
}

# Perform file backup
backup_files() {
    echo "Starting file backups..."
    check_storage "10GB"

    LAST_BACKUP_TIME=$(date -d "24 hours ago" +"%Y-%m-%d %H:%M:%S")
    CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")

    if [ "$WEEK_DAY" -eq $FULL_BACKUP_DAY ]; then
        echo "Performing full backup..."
        if [ $ARCHIVE_DIRECTLY_TO_SERVER -eq 1 ]; then
            FULL_BACKUP_FILE="${FULL_BACKUP_PREFIX}.7z"
            FULL_BACKUP_FILE_PATH="$CLONE_PATH/full_backup/$FULL_BACKUP_FILE"

            echo "Deleting existing full backup files: ${FULL_BACKUP_FILE_PATH}.*"
            find "$CLONE_PATH/full_backup" -name "${FULL_BACKUP_FILE}.*" -exec rm -f {} \;

            if [ $SHOW_PROGRESS -eq 1 ]; then
                $SEVENZIP a -mx0 -v5g "$FULL_BACKUP_FILE_PATH" $BACKUP_DIRS -bsp1 -y
            else
                $SEVENZIP a -mx0 -v5g "$FULL_BACKUP_FILE_PATH" $BACKUP_DIRS -y
            fi

            echo "Verifying full backup..."
            $SEVENZIP t "${FULL_BACKUP_FILE_PATH}."*
            if [ $? -ne 0 ]; then
                local message="Validation of full backup archive failed"
                send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                return 1
            fi
        else
            for dir in $BACKUP_DIRS; do
                if [ $SHOW_PROGRESS -eq 1 ]; then
                    rsync -a --delete --relative --progress --ignore-missing-args $dir $FULL_BACKUP_PATH/
                else
                    rsync -a --delete --relative --ignore-missing-args $dir $FULL_BACKUP_PATH/
                fi
                if [ $? -ne 0 ]; then
                    local message="Full backup failed for directory $dir"
                    send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                    return 1
                fi
            done
            echo "Compressing full backup..."
            if [ $RETAIN_ALL_BACKUPS -eq 1 ]; then
                FULL_BACKUP_FILE="${FULL_BACKUP_PREFIX}_$(date +"%Y%m%d").7z"
            else
                FULL_BACKUP_FILE="${FULL_BACKUP_PREFIX}.7z"
                echo "Deleting existing full backup files: ${FULL_BACKUP_PATH}/${FULL_BACKUP_FILE}.*"

                find "$FULL_BACKUP_PATH" -name "${FULL_BACKUP_FILE}.*" -exec rm -f {} \;
                sleep 1
                if ls "${BACKUP_SERVER_PATH}/${FULL_BACKUP_FILE}."* 1> /dev/null 2>&1; then
                    echo "Failed to delete existing full backup files: ${FULL_BACKUP_PATH}/${FULL_BACKUP_FILE}.*"
                    local message="Failed to delete existing full backup files: ${FULL_BACKUP_PATH}/${FULL_BACKUP_FILE}.*"
                    send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                    return 1
                fi
            fi

            FULL_BACKUP_FILE_PATH="$FULL_BACKUP_PATH/$FULL_BACKUP_FILE"

            if [ $SHOW_PROGRESS -eq 1 ]; then
                $SEVENZIP a -mx0 -v5g "$FULL_BACKUP_FILE_PATH" $FULL_BACKUP_PATH/* -bsp1 -y
            else
                $SEVENZIP a -mx0 -v5g "$FULL_BACKUP_FILE_PATH" $FULL_BACKUP_PATH/* -y
            fi

            if [ $VERIFY -eq 1 ]; then
                echo "Verifying full backup..."
                $SEVENZIP t "${FULL_BACKUP_FILE_PATH}."*
                if [ $? -ne 0 ]; then
                    local message="Validation of full backup archive failed"
                    send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                    return 1
                fi
            fi

            echo "Cloning full backup files to backup server path: ${CLONE_PATH}.*"
            clone_to_backup_server "${FULL_BACKUP_FILE_PATH}."* "$CLONE_PATH/full_backup"
            if [ $? -ne 0 ]; then
                local message="Cloning full backup to Backup Server Path failed"
                send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                return 1
            fi
        fi

    elif is_incremental_backup_day; then
        echo "Performing incremental backup..."
        echo "Cleaning incremental backup folder: $INCREMENTAL_BACKUP_PATH/$WEEK_DAY"
        rm -rf "$INCREMENTAL_BACKUP_PATH/$WEEK_DAY"
        rm -rf /tmp/changed_files.txt
        mkdir -p "$INCREMENTAL_BACKUP_PATH/$WEEK_DAY"

        for dir in $BACKUP_DIRS; do
            echo "Finding changed files in $dir..."
            find $dir -type f -newermt "-24 hours" >>/tmp/changed_files.txt
        done

        if [ -s /tmp/changed_files.txt ]; then
            echo "Files to be backed up:"
            cat /tmp/changed_files.txt | tr '\0' '\n'
            if [ $SHOW_PROGRESS -eq 1 ]; then
                rsync -a --delete --relative --progress --ignore-missing-args --files-from=/tmp/changed_files.txt / $INCREMENTAL_BACKUP_PATH/$WEEK_DAY/
            else
                rsync -a --delete --relative --ignore-missing-args --files-from=/tmp/changed_files.txt / $INCREMENTAL_BACKUP_PATH/$WEEK_DAY/
            fi
            if [ $? -ne 0 ]; then
                local message="Incremental backup failed"
                send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                return 1
            fi
        else
            echo "No files to backup incrementally."
        fi

        if [ "$(ls -A $INCREMENTAL_BACKUP_PATH/$WEEK_DAY)" ]; then
            echo "Compressing incremental backup..."
            if [ $RETAIN_ALL_BACKUPS -eq 1 ]; then
                INCREMENTAL_BACKUP_FILE="${INCREMENTAL_BACKUP_PREFIX}_$(date +"%Y%m%d").7z"
            else
                INCREMENTAL_BACKUP_FILE="${INCREMENTAL_BACKUP_PREFIX}_$WEEK_DAY.7z"
            fi
            INCREMENTAL_BACKUP_FILE_PATH="$INCREMENTAL_BACKUP_PATH/$INCREMENTAL_BACKUP_FILE"

            echo "Deleting existing incremental backup files: ${INCREMENTAL_BACKUP_FILE_PATH}.*"
            find "$INCREMENTAL_BACKUP_PATH" -name "${INCREMENTAL_BACKUP_FILE}.*" -exec rm -f {} \;
            sleep 1

            echo "Deleting existing incremental backup files: ${INCREMENTAL_BACKUP_FILE_PATH}.*"
            find "$CLONE_PATH/daily_backup/" -name "${INCREMENTAL_BACKUP_FILE}.*" -exec rm -f {} \;
            sleep 1
            
            if ls "${INCREMENTAL_BACKUP_FILE_PATH}."* 1>/dev/null 2>&1; then
                echo "Failed to delete existing incremental backup files: ${INCREMENTAL_BACKUP_FILE_PATH}.*"
                local message="Failed to delete existing incremental backup files: ${INCREMENTAL_BACKUP_FILE_PATH}.*"
                send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                return 1
            fi
            if [ $ARCHIVE_DIRECTLY_TO_SERVER -eq 1 ]; then
                INCREMENTAL_BACKUP_FILE_PATH="$CLONE_PATH/daily_backup/$INCREMENTAL_BACKUP_FILE"

                if [ $SHOW_PROGRESS -eq 1 ]; then
                    $SEVENZIP a -mx0 -v1g "$INCREMENTAL_BACKUP_FILE_PATH" $INCREMENTAL_BACKUP_PATH/$WEEK_DAY/* -bsp1 -y
                else
                    $SEVENZIP a -mx0 -v1g "$INCREMENTAL_BACKUP_FILE_PATH" $INCREMENTAL_BACKUP_PATH/$WEEK_DAY/* -y
                fi
            else
                if [ $SHOW_PROGRESS -eq 1 ]; then
                    $SEVENZIP a -mx0 -v1g "$INCREMENTAL_BACKUP_FILE_PATH" $INCREMENTAL_BACKUP_PATH/$WEEK_DAY/* -bsp1 -y
                else
                    $SEVENZIP a -mx0 -v1g "$INCREMENTAL_BACKUP_FILE_PATH" $INCREMENTAL_BACKUP_PATH/$WEEK_DAY/* -y
                fi
                if $SEVENZIP t "${INCREMENTAL_BACKUP_FILE_PATH}."* >/dev/null 2>&1; then
                    echo "Incremental backup successful."
                else
                    local message="Incremental backup archive failed"
                    send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                    return 1
                fi
            fi

            echo "Verifying incremental backup..."
            if [ $ARCHIVE_DIRECTLY_TO_SERVER -eq 1 ]; then
                $SEVENZIP t "${CLONE_PATH}/daily_backup/${INCREMENTAL_BACKUP_FILE}."*
            else
                $SEVENZIP t "${INCREMENTAL_BACKUP_FILE_PATH}."*
            fi

            if [ $? -ne 0 ]; then
                local message="Validation of incremental backup archive failed"
                send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                return 1
            fi

            if [ $ARCHIVE_DIRECTLY_TO_SERVER -eq 0 ]; then
                if [ "$CLONE_TO_BACKUP_SERVER" -eq 1 ]; then
                    echo "Clone incremental backup file to $CLONE_PATH/daily_backup/${INCREMENTAL_BACKUP_FILE}.*"
                    clone_to_backup_server "${INCREMENTAL_BACKUP_FILE_PATH}."* "${CLONE_PATH}/daily_backup/"

                    if [ $? -ne 0 ]; then
                        local message="Copying incremental backup to $CLONE_PATH failed"
                        send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                        return 1
                    fi
                fi
            fi
        else
            echo "No files to backup incrementally."
        fi
    else
        echo "No backup scheduled for today."
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    echo "Cleaning up old backups..."
    if [ $RETAIN_ALL_BACKUPS -eq 0 ]; then
        find $BACKUP_SERVER_PATH -name "${INCREMENTAL_BACKUP_PREFIX}_*.7z" -mtime +7 -exec rm -rf {} \;
        find $BACKUP_SERVER_PATH -name "${FULL_BACKUP_PREFIX}_*.7z" -mtime +30 -exec rm -rf {} \;
    fi
}

# Main function for full MySQL backup
full_backup_mysql_main() {
    echo "Starting full MySQL backups..."
    DBS="$($MYSQL -u $MyUSER -h $MyHOST -Bse 'show databases')"
    total_dbs=$(echo "$DBS" | wc -l)
    db_count=0
    for db in $DBS; do
        skipdb=0
        for ignore in $IGNORE_DB; do
            if [ "$db" == "$ignore" ]; then
                skipdb=1
                break
            fi
        done
        if [ "$skipdb" -eq 0 ]; then
            db_count=$((db_count + 1))
            echo "Backing up database ($db_count/$total_dbs): $db"
            full_backup_mysql $db
            if [ $? -ne 0 ]; then
                local message="MySQL full backup failed for database $db"
                send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                return 1
            fi

            if [ $VERIFY -eq 1 ]; then
                validate_mysql_backup $db $MYSQL_PATH $BINLOG_BACKUP_PATH
                if [ $? -ne 0 ]; then
                    local message="Validation of MySQL full backup failed for database $db"
                    send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                    return 1
                fi
            fi
        fi
    done
}

# Perform incremental MySQL backup
incremental_backup_mysql() {
    local db_name=$1
    local backup_path=$2
    local binlog_path=$3

    if [ $INCREMENTAL_DB_BACKUP_METHOD -eq 0 ]; then
        echo "Performing incremental backup using binlog"

        if [ ! -d "$binlog_path" ]; then
            mkdir -p "$binlog_path"
        else
            rm -f "$binlog_path"/*
        fi

        current_hour=$(date +%H)
        if [ $current_hour -ge 7 ]; then
            start_time=$(date -d 'today 00:00:00' +"%Y-%m-%d %H:%M:%S")
            end_time=$(date +"%Y-%m-%d %H:%M:%S")
        else
            start_time=$(date -d 'yesterday 00:00:00' +"%Y-%m-%d %H:%M:%S")
            end_time=$(date -d 'yesterday 23:59:59' +"%Y-%m-%d %H:%M:%S")
        fi

        binlog_files=$(mysql -u $MyUSER -h $MyHOST -e "SHOW BINARY LOGS;" | awk '{print $1}' | grep -v "Log_name")

        for binlog in $binlog_files; do
            if [ -z "$MyPASS" ]; then
                $MYSQLBINLOG --read-from-remote-server --host=$MyHOST --user=$MyUSER --start-datetime="$start_time" --stop-datetime="$end_time" $binlog >"$binlog_path/$binlog"
            else
                $MYSQLBINLOG --read-from-remote-server --host=$MyHOST --user=$MyUSER --password=$MyPASS --start-datetime="$start_time" --stop-datetime="$end_time" $binlog >"$binlog_path/$binlog"
            fi

            sleep 1
            if [ $? -ne 0 ]; then
                echo "Failed to backup binlog $binlog"
                return 1
            fi

            if [ -f "$binlog_path/$binlog" ]; then
                binlog_size=$(stat -c%s "$binlog_path/$binlog")
                if [ $binlog_size -ge 1024 ]; then
                    valid_binlog_files+=("$binlog_path/$binlog")
                fi
            fi
        done

        if [ ${#valid_binlog_files[@]} -eq 0 ]; then
            rm -f "$binlog_path/$binlog"
            echo "No data to backup."
            return 0
        fi

        echo "Backup of binlog files completed successfully"

        if [ "$(ls -A $binlog_path)" ]; then
            echo "Compressing binlog files..."
            if [ $RETAIN_ALL_BACKUPS -eq 1 ]; then
                BINLOG_BACKUP_FILE="${BINLOG_BACKUP_PREFIX}_$(date +"%Y%m%d").7z"
            else
                BINLOG_BACKUP_FILE="${BINLOG_BACKUP_PREFIX}_$WEEK_DAY.7z"
            fi
            BINLOG_BACKUP_FILE_PATH="$BINLOG_BACKUP_PATH/$BINLOG_BACKUP_FILE"
            rm -rf $BINLOG_BACKUP_FILE_PATH

            if [ $SHOW_PROGRESS -eq 1 ]; then
                for binlog in $(find "$binlog_path" -type f); do
                    binlog_name=$(basename "$binlog")

                    $PV "$binlog" | $SEVENZIP a -si"$binlog_name" -mx0 "$BINLOG_BACKUP_FILE_PATH"

                    if [ $? -ne 0 ]; then
                        echo "7z compression failed for binlog file $binlog"
                        return 1
                    fi
                done
            else
                $SEVENZIP a -mx0 "$BINLOG_BACKUP_FILE_PATH" "$binlog_path/*"

                if [ $? -ne 0 ]; then
                    echo "7z compression failed for binlog files"
                    return 1
                fi
            fi

            sleep 1

            if [ $CLONE_TO_BACKUP_SERVER -eq 1 ]; then
                clone_to_backup_server "$BINLOG_BACKUP_FILE_PATH" "${CLONE_PATH}/mysql_incremental/"
            fi
        fi
    else
        echo "Performing incremental backup using full dump for database: $db_name"
        local incremental_file="${backup_path}/${db_name}_incremental_${WEEK_DAY}.sql"

        if [ -z "$MyPASS" ]; then
            if [ $SHOW_PROGRESS -eq 1 ]; then
                $MYSQLDUMP -u $MyUSER -h $MyHOST $db_name --single-transaction --quick --flush-logs | $PV >"$incremental_file"
            else
                $MYSQLDUMP -u $MyUSER -h $MyHOST $db_name --single-transaction --quick --flush-logs >"$incremental_file"
            fi
        else
            if [ $SHOW_PROGRESS -eq 1 ]; then
                $MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db_name --single-transaction --quick --flush-logs | $PV >"$incremental_file"
            else
                $MYSQLDUMP -u $MyUSER -h $MyHOST -p$MyPASS $db_name --single-transaction --quick --flush-logs >"$incremental_file"
            fi
        fi

        if [ $? -ne 0 ]; then
            echo "MySQL incremental backup failed for database $db_name"
            return 1
        fi

        echo "Compressing incremental backup for database: $db_name"
        if [ $SHOW_PROGRESS -eq 1 ]; then
            $PV "$incremental_file" | $SEVENZIP a -si -mx0 "${incremental_file}.7z"
        else
            $SEVENZIP a -mx0 "${incremental_file}.7z" "$incremental_file"
        fi
        if [ $? -ne 0 ]; then
            local message="7z compression failed for incremental backup $incremental_file"
            send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
            return 1
        fi

        if [ $VERIFY -eq 1 ]; then
            validate_mysql_backup "$db_name" "$incremental_file" ""
        fi

        if [ $CLONE_TO_BACKUP_SERVER -eq 1 ]; then
            clone_to_backup_server "${incremental_file}.7z" "${CLONE_PATH}/mysql_incremental/"
        fi
    fi
}

# Main function for incremental MySQL backup
incremental_backup_mysql_main() {
    echo "Starting incremental MySQL backups..."

    if [ $INCREMENTAL_DB_BACKUP_METHOD -eq 0 ]; then
        incremental_backup_mysql "" $MYSQL_PATH $BINLOG_BACKUP_PATH/$WEEK_DAY
        if [ $? -ne 0 ]; then
            local message="MySQL incremental backup failed"
            send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
            return 1
        fi
        if [ $VERIFY -eq 1 ]; then
            validate_binlog_backup "$BINLOG_BACKUP_PATH/$WEEK_DAY/${BINLOG_BACKUP_PREFIX}_$WEEK_DAY.7z"
            if [ $? -ne 0 ]; then
                local message="MySQL binlog validation failed"
                send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                return 1
            fi
        fi
    else
        DBS="$($MYSQL -u $MyUSER -h $MyHOST -Bse 'show databases')"
        for db in $DBS; do
            skipdb=0
            for ignore in $IGNORE_DB; do
                if [ "$db" == "$ignore" ]; then
                    skipdb=1
                    break
                fi
            done
            if [ "$skipdb" -eq 0 ]; then
                incremental_backup_mysql $db $MYSQL_PATH $BINLOG_BACKUP_PATH
                if [ $? -ne 0 ]; then
                    local message="MySQL incremental backup failed for database $db"
                    send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                    return 1
                fi
                if [ $VERIFY -eq 1 ]; then
                    validate_mysql_backup $db $MYSQL_PATH $BINLOG_BACKUP_PATH
                    if [ $? -ne 0 ]; then
                        local message="MySQL incremental validation failed for database $db"
                        send_email $EMAIL "Backup Error on $SERVER" "$message" "$SENDER_NAME"
                        return 1
                    fi
                fi
            fi
        done
    fi
}

# Start MySQL backup process
backup_mysql() {
    if [ "$WEEK_DAY" -eq $FULL_BACKUP_DAY ]; then
        full_backup_mysql_main
    elif is_incremental_backup_day; then
        incremental_backup_mysql_main
    else
        echo "No MySQL backup scheduled for today."
    fi
}

# Validate MySQL backups
validate_mysql_backup() {
    local db_name=$1
    local backup_path=$2
    local binlog_path=$3

    echo "Validating backup for database: $db_name"

    local temp_db="${db_name}_temp"
    if [ -z "$MyPASS" ]; then
        $MYSQL -u $MyUSER -h $MyHOST -e "CREATE DATABASE $temp_db;"
    else
        $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "CREATE DATABASE $temp_db;"
    fi
    if [ $? -ne 0 ]; then
        echo "Failed to create temporary database $temp_db"
        return 1
    fi

    echo "Restoring full backup to temporary database..."
    if [ $RETAIN_ALL_BACKUPS -eq 1 ]; then
        full_backup_file=$(ls -t $backup_path/$db_name.*.7z | head -n 1)
    else
        full_backup_file="$backup_path/$db_name.7z"
    fi
    if [ -f "$full_backup_file" ]; then
        echo "SET foreign_key_checks = 0; SET unique_checks = 0; SET autocommit = 0;" >temp_script.sql
        $SEVENZIP e -so "$full_backup_file" >>temp_script.sql
        echo "SET foreign_key_checks = 1; SET unique_checks = 1; COMMIT;" >>temp_script.sql
        if [ -z "$MyPASS" ]; then
            $MYSQL -u $MyUSER -h $MyHOST $temp_db <temp_script.sql
        else
            $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS $temp_db <temp_script.sql
        fi
        rm temp_script.sql
        if [ $? -ne 0 ]; then
            echo "Failed to restore full backup to temporary database $temp_db"
            if [ -z "$MyPASS" ]; then
                $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
            else
                $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
            fi
            return 1
        fi
    else
        if [ $AUTO_GENERATE_DB_BACKUP_IF_NOT_FOUND -eq 1 ]; then
            echo "Full backup for database $db_name not found, generating new full backup..."
            full_backup_mysql $db_name $backup_path
        else
            echo "Full backup for database $db_name not found and AUTO_GENERATE_DB_BACKUP_IF_NOT_FOUND is set to 0. Skipping validation."
            if [ -z "$MyPASS" ]; then
                $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
            else
                $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
            fi
            return 1
        fi
    fi

    if [ $INCREMENTAL_DB_BACKUP_METHOD -eq 0 ]; then
        echo "Applying binlog files to temporary database..."
        binlog_files=$(ls $binlog_path/mysql-bin.*)
        for binlog in $binlog_files; do
            if [ ! -f "$binlog_path/$binlog" ]; then
                echo "Extracting binlog file $binlog from archive..."
                if [ $ARCHIVE_DIRECTLY_TO_SERVER -eq 1 ]; then
                    $SEVENZIP e "$CLONE_PATH/${BINLOG_BACKUP_PREFIX}_$WEEK_DAY.7z" -o"$binlog_path" "$binlog"
                else
                    $SEVENZIP e "$BACKUP_PATH/${BINLOG_BACKUP_PREFIX}_$WEEK_DAY.7z" -o"$binlog_path" "$binlog"
                fi
                if [ $? -ne 0 ]; then
                    echo "Failed to extract binlog file $binlog"
                    return 1
                fi
            fi
            if [ -z "$MyPASS" ]; then
                $MYSQLBINLOG $binlog_path/$binlog | $MYSQL -u $MyUSER -h $MyHOST $temp_db
            else
                $MYSQLBINLOG $binlog_path/$binlog | $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS $temp_db
            fi
            if [ $? -ne 0 ]; then
                echo "Failed to apply binlog $binlog to temporary database $temp_db"
                if [ -z "$MyPASS" ]; then
                    $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
                else
                    $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
                fi
                return 1
            fi
        done
    else
        echo "Applying incremental full backups to temporary database..."
        incremental_backup_files=$(ls $backup_path/${db_name}_incremental_*.7z)
        for backup_file in $incremental_backup_files; do
            echo "SET foreign_key_checks = 0; SET unique_checks = 0; SET autocommit = 0;" >temp_script.sql
            $SEVENZIP e -so "$backup_file" >>temp_script.sql
            echo "SET foreign_key_checks = 1; SET unique_checks = 1; COMMIT;" >>temp_script.sql
            if [ -z "$MyPASS" ]; then
                $MYSQL -u $MyUSER -h $MyHOST $temp_db <temp_script.sql
            else
                $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS $temp_db <temp_script.sql
            fi
            rm temp_script.sql
            if [ $? -ne 0 ]; then
                echo "Failed to apply incremental backup $backup_file to temporary database $temp_db"
                if [ -z "$MyPASS" ]; then
                    $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
                else
                    $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
                fi
                return 1
            fi
        done
    fi

    echo "Running validation queries..."
    if [ -z "$MyPASS" ]; then
        TABLES=$($MYSQL -u $MyUSER -h $MyHOST -e "SHOW TABLES;" $temp_db)
    else
        TABLES=$($MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "SHOW TABLES;" $temp_db)
    fi
    if [ $? -ne 0 ]; then
        echo "Failed to list tables in database $temp_db"
        if [ -z "$MyPASS" ]; then
            $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
        else
            $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
        fi
        return 1
    fi
    echo "Tables in database $temp_db:"
    echo "$TABLES"

    if [ -z "$MyPASS" ]; then
        $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
    else
        $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
    fi
    echo "Validation completed successfully for database: $db_name"
}

# Validate binlog backups
validate_binlog_backup() {
    local binlog_backup_file=$1
    local binlog_path="/tmp/binlog_extract"
    local db_list_file="/tmp/db_list.txt"
    local sql_file="/tmp/temp_sql.sql"

    echo "Validating binlog backup: $binlog_backup_file"

    mkdir -p "$binlog_path"
    $SEVENZIP x "$binlog_backup_file" -o"$binlog_path"

    if [ $? -ne 0 ]; then
        echo "Failed to extract binlog backup for validation"
        return 1
    fi

    extract_tables_from_binlog "$binlog_path/mysql-bin.*" "$db_list_file"

    if [ ! -f "$db_list_file" ]; then
        echo "No databases found in binlog file."
        return 1
    fi

    while read -r db_name; do
        local temp_db="${db_name}_temp"

        echo "Validating database: $db_name"

        if [ -z "$MyPASS" ]; then
            $MYSQL -u $MyUSER -h $MyHOST -e "CREATE DATABASE IF NOT EXISTS $temp_db;"
        else
            $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "CREATE DATABASE IF NOT EXISTS $temp_db;"
        fi
        if [ $? -ne 0 ]; then
            echo "Failed to create temporary database $temp_db"
            return 1
        fi

        for binlog in $(ls $binlog_path/mysql-bin.*); do
            extract_and_filter_sql $binlog $db_name $sql_file
            if [ -z "$MyPASS" ]; then
                $MYSQL -u $MyUSER -h $MyHOST $temp_db <$sql_file
            else
                $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS $temp_db <$sql_file
            fi
            if [ $? -ne 0 ]; then
                echo "Failed to apply binlog $binlog to temporary database $temp_db"
                if [ -z "$MyPASS" ]; then
                    $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
                else
                    $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
                fi
                return 1
            fi
        done

        echo "Running validation queries for database: $temp_db"
        if [ -z "$MyPASS" ]; then
            TABLES=$($MYSQL -u $MyUSER -h $MyHOST -e "SHOW TABLES;" $temp_db)
        else
            TABLES=$($MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "SHOW TABLES;" $temp_db)
        fi
        if [ $? -ne 0 ]; then
            echo "Failed to list tables in database $temp_db"
            if [ -z "$MyPASS" ]; then
                $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
            else
                $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
            fi
            return 1
        fi
        echo "Tables in database $temp_db:"
        echo "$TABLES"

        if [ -z "$MyPASS" ]; then
            $MYSQL -u $MyUSER -h $MyHOST -e "DROP DATABASE $temp_db;"
        else
            $MYSQL -u $MyUSER -h $MyHOST -p$MyPASS -e "DROP DATABASE $temp_db;"
        fi
        echo "Validation completed successfully for database: $db_name"
    done <"$db_list_file"

    rm -rf "$binlog_path"
    rm -f "$db_list_file"
    rm -f "$sql_file"
    echo "Binlog validation completed successfully"
}

# Check and install required tools before executing the script
install_required_tools

# Execute backup process
echo "Checking available storage..."
check_storage "100GB"

backup_mysql
if [ $? -ne 0 ]; then
    send_email $EMAIL "Backup Error on $SERVER" "MySQL backup failed" "$SENDER_NAME"
    exit 1
fi
backup_files
if [ $? -ne 0 ]; then
    send_email $EMAIL "Backup Error on $SERVER" "File backup failed" "$SENDER_NAME"
    exit 1
fi

echo "Backup process completed successfully."
