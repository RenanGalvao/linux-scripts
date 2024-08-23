#!/bin/bash
VERSION=1.0.1
DRY_RUN=false

##
# VARS
##
declare -r DOCKER_VOLUMES_FOLDER="/var/lib/docker/volumes"
declare -r BACKUP_ROOT_FOLDER="/tmp/backup"

declare -r BACKUP_DEST_FOLDER="/backup/<domain>/daily"
declare -r BACKUP_DEST_HOST="<server-ip>"

# [<docker service>] = <volume name> <volume name 2>
declare -rA SERVICES=(
    [service]="volume_name volume_name2"
    [service2]="volume_name3"
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
    
    echo $(find "$folder" -type f -printf "%T@ %p\n" | sort -n | cut -d' ' -f 2 | tail -n 1)
}

function getFileByDate() {
    local folder=$1
    local date=$2
    local date
    
    if [ -z "$folder" ]; then
        echo "You must pass the folder name. Exiting..."
        exit 1
    fi
    
    if ! [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Invalid date format, expected: yyyy-mm-dd. Exiting..."
        exit 1
    fi
    
    echo $(find "$folder" -type f -newermt "$date 00:00:00" ! -newermt "$date 23:59:59" -printf "%T@ %p\n" | sort -n | cut -d' ' -f 2 | tail -n 1)
}

function getContainerFromServiceName() {
    local service=$1
    
    if [ -z "$service"]; then
        echo "You must pass the service name. Exiting..."
        exit 1
    fi
    
    echo $(docker container ls --format='{{.Names}}'| grep "$service" | sort | head -n 1)
}


##
# SETUP
##
function setup() {
    # Create backup folder for every volume of every service
    for service in ${!SERVICES[@]}
    do
        for volumes in ${SERVICES[$service]}
        do
            for volume in $volumes
            do
                echoCommand "mkdir -p ${BACKUP_ROOT_FOLDER}/${volume}"
                
                if [ $DRY_RUN != true ]; then
                    mkdir -p "${BACKUP_ROOT_FOLDER}/${volume}"
                fi
            done
        done
    done
    
    echoCommand "echo -e \"
    SHELL=/bin/sh
    PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
    
    59 12 * * * root $(pwd)/$(basename $0) run\" > /etc/cron.d/backup-client"
    
    if [ $DRY_RUN != true ]; then
        # Set crontab
        echo -e "
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

59 12 * * * root $(pwd)/$(basename $0) run" > /etc/cron.d/backup-client
    fi
}


##
# Backup Functions
##
function deleteOldBackupVolumes() {
    # delete backups older than 7 days
    echoCommand "find ${BACKUP_ROOT_FOLDER}/ -type f -mtime +7 -delete"
    if [ $DRY_RUN != true ]; then
        find "${BACKUP_ROOT_FOLDER}/" -type f -mtime +7 -delete
    fi
}

function backupExternal() {
    for service in ${!SERVICES[@]}
    do
        for volumes in ${SERVICES[$service]}
        do
            for volume in $volumes
            do
                local mostRecentFile=$(getMostRecentBackup "${BACKUP_ROOT_FOLDER}/${volume}")
                
                echoCommand "rsync -avz $mostRecentFile root@${BACKUP_DEST_HOST}:${BACKUP_DEST_FOLDER}/${volume}"
                if [ $DRY_RUN != true ]; then
                    rsync -avz "$mostRecentFile" "root@${BACKUP_DEST_HOST}:${BACKUP_DEST_FOLDER}/${volume}"
                fi
            done
        done
    done
}

function backupDockerVolumes() {
    deleteOldBackupVolumes
    for service in ${!SERVICES[@]}
    do
        for volumes in ${SERVICES[$service]}
        do
            for volume in $volumes
            do
                echoCommand "tar czfv ${BACKUP_ROOT_FOLDER}/${volume}/${volume}-$(date +%F).tar.gz -C ${DOCKER_VOLUMES_FOLDER}/${volume} ."
                if [ $DRY_RUN != true ]; then
                    tar czfv "${BACKUP_ROOT_FOLDER}/${volume}/${volume}-$(date +%F).tar.gz" -C "${DOCKER_VOLUMES_FOLDER}/${volume}" .
                fi
            done
        done
    done
    backupExternal
}

function _restoreBackupDockerVolumesUsage() {
    echo -e "Usage:
    backup:restore <service>            - list available restore dates
    backup:restore <service> yyyy-mm-dd - restore service data\n"
    echoCommand "Services available:"
    
    for service in ${!SERVICES[@]}
    do
        echo -e "$service - restore ${SERVICES[$service]} volume(s)"
    done
}

function restoreBackupDockerVolumes() {
    local service=$2
    local date=$3
    
    # +1 since backup:restore counts as argument
    # backup:restore service case
    if [ $# -eq "$((1+1))" ]; then
        local match=0
        for srvc in ${!SERVICES[@]}; do
            if [ $service == $srvc ]; then
                match=1
                break
            fi
        done
        
        if [ $match -eq 1 ]; then
            local volumes=${SERVICES[$service]}
            for volume in $volumes
            do
                local volumeFolder="${BACKUP_ROOT_FOLDER}/${volume}/"
                
                echoCommand "Available Dates for $volume:"
                ls -lah "$volumeFolder"
            done
            exit 0
        else
            _restoreBackupDockerVolumesUsage
            exit 1
        fi
        
        # fallback case
        elif [ $# -ne "$((2+1))" ]; then
        _restoreBackupDockerVolumesUsage
        exit 1
    fi
    
    
    local volumes=${SERVICES[$service]}
    for volume in $volumes
    do
        local file=$(getFileByDate "${BACKUP_ROOT_FOLDER}/${volume}" $date)
        
        if [ ! -f "$file" ]; then
            echo "File $file doesn't exist. Exiting..."
            exit 1
        fi
    done
    
    echoCommand "docker container stop $(getContainerFromServiceName $service)"
    if [ $DRY_RUN != true ]; then
        docker container stop "$(getContainerFromServiceName ${service})"
    fi
    
    for volume in $volumes
    do
        local file=$(getFileByDate "${BACKUP_ROOT_FOLDER}/${volume}" $date)

        echoCommand "tar xzvf $file -C ${DOCKER_VOLUMES_FOLDER}/${volume}/"
        if [ $DRY_RUN != true ]; then
            tar xzvf "$file" -C "${DOCKER_VOLUMES_FOLDER}/${volume}/"
        fi
    done
    
    echoCommand "docker compose up -d --no-deps $service"
    if [ $DRY_RUN != true ]; then
        docker compose up -d --no-deps "$service"
    fi
}


##
# Interface
##
HELP_MESSAGE="Available commands are:
run                 - create .tar.gz files from volumes in $BACKUP_ROOT_FOLDER
external            - sends backup to external VPS
restore             - restores volume data from backup file
delete-old          - removes old backup files (7 day old)

setup               - setup enviroment ro run daily backups

Available options:
-h                  - print help message (this one)
-n                  - perform a trial run with no changes made
-v                  - print the version"

while getopts ":nvh" opt; do
    case $opt in
        v)
            echo "Backup Client v${VERSION}"
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
    run)
    backupDockerVolumes;;
    external)
    backupExternal;;
    restore)
    restoreBackupDockerVolumes "$@";;
    delete-old)
    deleteOldBackupVolumes;;
    
    setup)
    setup;;
    
    *)
        echo "\"$command\" not available. Use $(basename $0) -h to see available commands.";;
esac