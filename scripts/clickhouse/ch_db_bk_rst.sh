#!/usr/bin/env bash

backup_ch_db() {
  clickhouse-client -mn --send_timeout "${CH_TIMEOUT}" --receive_timeout "${CH_TIMEOUT}" --max_execution_time "${CH_TIMEOUT}" --echo \
    -q "backup all except database system to S3('${BACKUP_LOCATION}/${INSTANCE_NAME}-${TIMESTAMP}', '${S3_KEYID}', '${S3_SECRET}')" \
    --host="localhost" --port="9000" \
    --user="$BACKUP_USER" \
    --password="$BACKUP_PASSWORD";
  return $?
}

restore_ch_db() {
  clickhouse-client -mn --send_timeout "${CH_TIMEOUT}" --receive_timeout "${CH_TIMEOUT}" --max_execution_time "${CH_TIMEOUT}" --echo \
    -q "restore all except database system from S3('${BACKUP_LOCATION}/${INSTANCE_NAME}-${TIMESTAMP}', '${S3_KEYID}', '${S3_SECRET}') SETTINGS allow_non_empty_tables=true" \
    --host="localhost" --port="9000" \
    --user="$BACKUP_USER" \
    --password="$BACKUP_PASSWORD";

  return $?
}

if [ "$#" -ne 9 ]; then
  echo "Usage:"
  echo "    backup/restore BACKUP_LOCATION S3_KEYID S3_SECRET INSTANCE_NAME TIMESTAMP CH_BACKUP_TIMEOUT"
  exit 1
fi

type=$1
BACKUP_LOCATION=$2
S3_KEYID=$3
S3_SECRET=$4
INSTANCE_NAME=$5
TIMESTAMP=$6
CH_TIMEOUT=$7

BACKUP_USER=$8
BACKUP_PASSWORD=$9

if [ "$type" == "backup" ]; then
    echo "backing up db"
    echo "  $INSTANCE_NAME"
    backup_ch_db

    result=$?
    exit $result
elif [ "$type" == "restore" ]; then
    echo "restoring db from backup"
    echo "  $INSTANCE_NAME"
    restore_ch_db

    result=$?
    exit $result
else
    echo "parameter error"
    exit 1
fi
