#!/bin/bash
VERSION=1.0.0
DRY_RUN=false

##
# VARS
##
declare -r BACKUP_ROOT_FOLDER="/backup"

# [<domain>] = <volume name> <volume name 2>
declare -rA DOMAINS=(
    ["domain1.example.com"]="volume_name_1 volume_name_2"
    ["domain2.example.com"]="volume_name_3"
)


##
# Shared Functions
##
function echoCommand() {
    local color='\033[0;32m' # green
    local noColor='\033[0m'
    local string=$1
    if [ -z "$string" ]; then
        echo "You must pass one string. Exiting..."
        exit 1
    fi
    
    echo -e "$color$string$noColor"
    
}

function getMostRecentBackup() {
    local folder=$1
    
    if [ -z "$folder" ]; then
        echo "You must pass the folder name. Exiting..."
        exit 1
    fi
    
    if [ $DRY_RUN != true ]; then
        echo $(find "$folder" -type f -printf "%T@ %p\n" | sort -n | cut -d' ' -f 2 | tail -n 1)
    else
        echo "${folder}/<most-recent-backup-file.tar.gz>"
    fi
}

function copyFromPeriodToPeriod() {
    local domain=$1
    local volume=$2
    local fromPeriod=$3
    local toPeriod=$4
    
    if [ -z "$domain" ]; then
        echo "You must pass the domain name. Exiting..."
        exit 1
    fi
    
    if [ -z "$volume" ]; then
        echo "You must pass the volume name. Exiting..."
        exit 1
    fi
    
    if [ -z "$fromPeriod" ]; then
        echo "You must pass from which period. Exiting..."
        exit 1
    fi
    
    if [ -z "$toPeriod" ]; then
        echo "You must pass to which period. Exiting..."
        exit 1
    fi
    
    local mostRecentFile=$(getMostRecentBackup "${BACKUP_ROOT_FOLDER}/${domain}/${fromPeriod}/${volume}")
    local from=$mostRecentFile
    local to="${BACKUP_ROOT_FOLDER}/${domain}/${toPeriod}/${volume}"
    
    echoCommand "cp $from $to"
    
    if [ $DRY_RUN != true ]; then
        cp "$from" "$to"
    fi
}

function removeOldBackups() {
    local period=$1
    local days=$2
    
    for domain in ${!DOMAINS[@]}
    do
        echoCommand "find ${BACKUP_ROOT_FOLDER}/${domain}/${period} -type f -mtime +${days} -delete"
        
        if [ $DRY_RUN != true ]; then
            find "${BACKUP_ROOT_FOLDER}/${domain}/${period}" -type f -mtime "+${days}" -delete
        fi
    done
}


##
# SETUP
##
function setup() {
    for domain in ${!DOMAINS[@]}
    do
        local periods=(
            "daily"
            "weekly"
            "monthly"
        )
        
        for period in ${periods[@]}
        do
            for volumes in ${DOMAINS[$domain]}
            do
                for volume in $volumes
                do
                    echoCommand "mkdir -p ${BACKUP_ROOT_FOLDER}/${domain}/${period}/${volume}"
                    if [ $DRY_RUN != true ]; then
                        mkdir -p "${BACKUP_ROOT_FOLDER}/${domain}/${period}/${volume}"
                    fi
                done
            done
        done
    done
    
    echoCommand "echo -e \"
    SHELL=/bin/sh
    PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
    
    0   12  *   *   *               $(pwd)/$(basename $0) job:daily
    15  12  *   *   6               $(pwd)/$(basename $0) job:weekly
    30  12  30  4,6,9,11 *          $(pwd)/$(basename $0) job:monthly
    30  12  31  1,3,5,7,8,10,12 *   $(pwd)/$(basename $0) job:monthly
    30  12  28  2   *               $(pwd)/$(basename $0) job:monthly
    \" > /etc/cron.d/backup-server"
    
    if [ $DRY_RUN != true ]; then
        # Set crontab
        echo -e "
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

0   12  *   *   *               $(pwd)/$(basename $0) job:daily
15  12  *   *   6               $(pwd)/$(basename $0) job:weekly
30  12  30  4,6,9,11 *          $(pwd)/$(basename $0) job:monthly
30  12  31  1,3,5,7,8,10,12 *   $(pwd)/$(basename $0) job:monthly
30  12  28  2   *               $(pwd)/$(basename $0) job:monthly
        " > /etc/cron.d/backup-server
    fi
}


##
# Daily
##
function removeOldBackupsDaily() {
    removeOldBackups "daily" 7
}


##
# Weekly
##
function copyFromDailyToWeekly() {
    for domain in ${!DOMAINS[@]}
    do
        for volumes in ${DOMAINS[$domain]}
        do
            for volume in $volumes
            do
                copyFromPeriodToPeriod "$domain" "$volume" "daily" "weekly"
            done
        done
    done
}

function removeOldBackupsWeekly() {
    removeOldBackups "weekly" 30
}


##
# Monthly
##
function copyFromWeeklyToMonthly() {
    for domain in ${!DOMAINS[@]}
    do
        for volumes in ${DOMAINS[$domain]}
        do
            for volume in $volumes
            do
                copyFromPeriodToPeriod "$domain" "$volume" "weekly" "monthly"
            done
        done
    done
}

function  removeOldBackupsMonthly() {
    removeOldBackups "monthly" 365
}


##
# Help and Description
##
HELP_MESSAGE="Available commands are:
job:daily           - run daily job
job:weekly          - run weekly job
job:monthly         - run monthly job

setup               - setup enviroment ro run daily backups

Available options:
-h                  - print help message (this one)
-n                  - perform a trial run with no changes made
-v                  - print the version"

while getopts ":nvh" opt; do
    case $opt in
        v)
            echo "Backup Server v${VERSION}"
        exit 0;;
        h)
            echo "$HELP_MESSAGE"
        exit 0;;
        n)
            DRY_RUN=true
        set -- $(echo $@);;
    esac
done

command=$1
if [ -z $command ]; then
    echo "$HELP_MESSAGE"
fi

case $command in
    job:daily)
    removeOldBackupsDaily;;
    job:weekly)
        copyFromDailyToWeekly
    removeOldBackupsWeekly;;
    job:monthly)
        copyFromWeeklyToMonthly
    removeOldBackupsMonthly;;
    
    setup)
    setup;;
    
    *)
        echo "\"$command\" not available. Use $(basename $0) -h to see available commands.";;
esac
