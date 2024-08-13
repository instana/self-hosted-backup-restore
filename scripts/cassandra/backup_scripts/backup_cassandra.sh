#!/usr/bin/env bash
#
#IBM Confidential
#5737-M96
#Copyright IBM Corp. 2014, 2024
#

set -o errexit
set -o pipefail
set -o nounset

CASSANDRA_SCRIPTS=/opt/cassandra/backup_scripts
#shellcheck source=/dev/null
. $CASSANDRA_SCRIPTS/cassandra.env
#shellcheck source=/dev/null
. $CASSANDRA_SCRIPTS/cassandra_functions.sh

main() {
  description 
  usage
  set_default_parameters
  read_cmd_line "$@" 
  set_parameters
  print_parameters | tee "$SCRIPT_LOG"

  test_force
  printf "%s  BACKUP KEYSPACE: %s\n" "$(date)" "$KEYSPACE_TO_BACKUP" | tee -a "$SCRIPT_LOG"
  backup |tee -a "$SCRIPT_LOG" 2>&1

  printf "%s ************************ \n" "$(date)"
  printf "%s Log file: %s \n" "$(date)" "$SCRIPT_LOG"  
}

#-------------------------------------------------------------------------------
# usage
# Description - Display script usage
#-------------------------------------------------------------------------------
description() {
  printf "\n# Description : The backup script will complete the backup in multiple phases - \n"
  printf "#  1. Take statistics of the keyspace(s) before backup \n"
  printf "#  2. Clear existed snapshots \n"
  printf "#  3. Take backup of keyspace(s) SCHEMA in temporary BACKUP_TEMP_DIR\n"
  printf "#  4. Take snapshot of keyspace(s) \n"
  printf "#  5. Copy snapshot to temporary BACKUP_TEMP_DIR \n"
  printf "#  6. Compact the temporary BACKUP_TEMP_DIR in one tar file and send it to BACKUP_DIR \n"
  printf "\n"
}

usage() {
  printf "\nUSAGE: %s " "$(basename "$0")"
  printf "\n   [ -k keyspace to backup ] # default is ALL keyspaces "
  printf "\n   [ -b  temporary backup dir ] # default is %s" "$BACKUP_TEMP_DIR"
  printf "\n   [ -d  datadir ] # default is %s" "$CASSANDRA_DATA"
  printf "\n   [ -s storagedir ] # default is %s" "$BACKUP_DIR"
  printf "\n   [ -u Cassandra username ]"
  printf "\n   [ -p Cassandra password ]"
  printf "\n   [ -log logdir ] # default is %s" "$LOG_PATH"
  printf "\n   [ -speed tardiskspeed ] # default is %s" "$TAR_SPEED_LIMIT"
  printf "\n   [ -f ] # for non interactive mode"
  printf "\n"
} # usage

read_cmd_line() {
  while [ $# != 0 ]; do
    case "$1" in          
      -b)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for temporary backup directory or use default=%s \n" "$BACKUP_TEMP_DIR"
          usage
          exit 1
        fi
        BACKUP_TEMP_DIR="$1"
        ;;
      -d)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the cassandra data directory or use default=%s \n" "$CASSANDRA_DATA"
          usage
          exit 1
        fi
        DATA_DIR="$1"
        ;;
      -u)
        shift
        USER="$1"
        ;;
      -p)
        shift
        PASS="$1"
        ;;
      -s)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the remote backup storage directory or use default=%s \n" "$BACKUP_DIR"
          usage
          exit 1
        fi
        REMOTE_BACKUP_DIR="$1"
        ;;	
      -k)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the keyspace to backup or use default=ALL} \n"
          usage
          exit 1
        fi
        KEYSPACE_TO_BACKUP="$1"
        ;;
      -log)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the log directory or use default=%s  \n" "$LOG_PATH"
          usage
          exit 1
        fi
        LOG_PATH="$1"
        ;;
      -speed)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the tar speed limit or use default=%s  \n" "$TAR_SPEED_LIMIT"
          usage
          exit 1
        fi
        TAR_SPEED_LIMIT="$1"
        ;;
      -f)
        FORCE=Y
        ;;
      -help)
        exit 1
        ;;
      *)
        exit 1
        ;;
      esac
      shift
  done
}

set_default_parameters() {
  KEYSPACE_TO_BACKUP="ALL"
  DATA_DIR="$CASSANDRA_DATA"
  REMOTE_BACKUP_DIR="$BACKUP_DIR"
}

set_parameters() {
 BACKUP_SNAPSHOT_DIR="$BACKUP_TEMP_DIR/$DATE_TIME/SNAPSHOTS"
 BACKUP_SCHEMA_DIR="$BACKUP_TEMP_DIR/$DATE_TIME/SCHEMA"
 BACKUP_STATS_DIR="$BACKUP_TEMP_DIR/$DATE_TIME/STATS"
 BACKUP_CONF_DIR="$BACKUP_TEMP_DIR/$DATE_TIME/CONF"

 # Script files
 if [ ! "$LOG_PATH" = "" ] ; then
    SCRIPT_LOG="${LOG_PATH}/${SCRIPT_NAME}-${TIMESTAMP}.log"
 else
    SCRIPT_LOG="/tmp/${SCRIPT_NAME}-${TIMESTAMP}.log"
 fi
}

print_parameters() {
  printf "\n"
  printf "********** START CONFIGURATION ***************** \n"
  printf "KEYSPACE_TO_BACKUP=%s \n" "$KEYSPACE_TO_BACKUP"
  printf "BACKUP_TEMP_DIR=%s \n" "$BACKUP_TEMP_DIR"
  printf "BACKUP_DIR=%s \n" "$REMOTE_BACKUP_DIR"
  printf "CASSANDRA_DATA=%s \n" "$DATA_DIR"
  printf "LOG_PATH=%s \n" "$LOG_PATH"
  printf "TAR_SPEED_LIMIT=%s \n" "$TAR_SPEED_LIMIT"
  printf "FORCE=%s \n" "$FORCE"
  printf "USER=%s \n" "$USER"
  printf "PASS=XXXX \n"
  printf "********** END CONFIGURATION ***************** \n"
  printf "\n"
}

main "$@"
