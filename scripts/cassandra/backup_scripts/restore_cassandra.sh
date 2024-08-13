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
  printf "%s  RESTORE a KEYSPACE \n" "$(date)" | tee -a "$SCRIPT_LOG"
  restore | tee -a "$SCRIPT_LOG"

  printf "%s ************************ \n" "$(date)"
  printf "%s Log file: %s \n" "$(date)" "$SCRIPT_LOG"
}

##-------------------------------------------------------------------------------
## Description - Display script usage
##-------------------------------------------------------------------------------
description() {
  printf "\n# Description : The restore script will complete the restore in multiple phases - \n"
  printf "1. Take statistics of the cassandra node before restore \n" 
  printf "2. Check if the keyspace exists and if it does not exist, create it using the schema cql file saved in the backup file \n"
  printf "3. Truncate all tables in keyspace  \n" 
  printf "4. Clear all files in commitlog directory \n"
  printf "5. Copy contents of desired snapshot to active keyspace. \n"
  printf "6. Refresh all tables in that keyspace \n"    
  printf "7. Take statistics of the cassandra node after restore and compare with statistics taken before backup, making sure number of keys per table is the same\n" 
  printf "\n"
}

usage() {
  printf "\nUSAGE: %s " "$(basename "$0")"
  printf "\n    -k keyspaceName  # compulsory parameter "    
  printf "\n   [ -h backup hostname] # if backup was done on a different hostname than %s " "$HOSTNAME"
  printf "\n   [ -b temporary backup dir  ] # default is %s " "$BACKUP_TEMP_DIR"
  printf "\n   [ -d  dataDir ] # default is %s" "$CASSANDRA_DATA"
  printf "\n   [ -t  snapshotTimestamp ] # timestamp of type date YYYY-MM-DD-HHMM-SS - default is latest"
  printf "\n   [ -s  storageDir ] # default is %s" "$BACKUP_DIR"
  printf "\n   [ -u Cassandra username ]"
  printf "\n   [ -p Cassandra password ]"
  printf "\n   [ -log logDir ] # default is %s" "$LOG_PATH"
  printf "\n   [ -f ]  # for non interactive mode"
  printf "\n   [ -i ]  # ignore num_tokens check"
  printf "\n"
  printf "\n"
}

read_cmd_line() {
  while [ $# != 0 ]; do
    case "$1" in          
      -b)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for backup directory or use default=%s \n" "$BACKUP"
          usage
          exit 1
        fi
        BACKUP_TEMP_DIR="$1"
        ;;
      -d)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the cassandra data directory or use default=%s/data \n" "$CASSANDRA_DATA"
          usage
          exit 1
        fi
        DATA_DIR="$1"
        ;;
      -s)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the remote backup storage directory  or use default = %s \n" "$BACKUP_DIR"
          usage
          exit 1
        fi
       REMOTE_BACKUP_DIR="$1"
       ;;
      -t)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the snaphot timestamp or use default = latest \n"
          usage
          exit 1
        fi
        SNAPSHOT_DATE_TO_RESTORE="$1"
        ;;
      -k)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the keyspace name   \n"
          usage
          exit 1
        fi
        KEYSPACE_TO_RESTORE="$1"
        ;;
      -h)
        shift
        if [ $# = 0 ]; then
          printf "\nPlease enter a value for the backup hostname   \n"
          usage
          exit 1
        fi
        BACKUP_HOSTNAME="$1"
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
      -f)
        FORCE=Y
        ;;
      -i)
        IGNORE_CHECK=Y
        ;;
      -u)
        shift
        USER="$1"
        ;;
      -p)
        shift
        PASS="$1"
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
  BACKUP_HOSTNAME=$HOSTNAME
  SNAPSHOT_DATE_TO_RESTORE="latest"
  DEFAULT_KEYSPACE="shared"
  KEYSPACE_TO_RESTORE="$DEFAULT_KEYSPACE"
  DATA_DIR="$CASSANDRA_DATA" 
  REMOTE_BACKUP_DIR="$BACKUP_DIR"
  IGNORE_CHECK=Y
}

set_parameters() {

  BACKUP_SNAPSHOT_DIR="$BACKUP_DIR/$DATE_TIME/SNAPSHOTS"
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
  printf "BACKUP_TEMP_DIR=%s \n" "$BACKUP_TEMP_DIR"
  printf "BACKUP_DIR=%s \n" "$REMOTE_BACKUP_DIR"
  printf "DATA_DIR=%s \n" "$DATA_DIR"
  printf "LOG_PATH=%s \n" "$LOG_PATH"
  printf "local hostname=%s \n" "$HOSTNAME"
  printf "BACKUP_HOSTNAME=%s \n" "$BACKUP_HOSTNAME"  
  printf "SNAPSHOT_DATE_TO_RESTORE=%s \n" "$SNAPSHOT_DATE_TO_RESTORE"
  printf "KEYSPACE_TO_RESTORE=%s \n" "$KEYSPACE_TO_RESTORE"
  printf "FORCE=%s \n" "$FORCE"  
  printf "IGNORE_CHECK=%s \n" "$IGNORE_CHECK" 
  printf "USER=%s \n" "$USER"
  printf "PASS=XXXX \n"
  printf "********** END CONFIGURATION ***************** \n"
  printf "\n"
} 

main "$@"
