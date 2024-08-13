#!/usr/bin/env bash

readonly POSTGRES_HOST=localhost
readonly POSTGRES_PORT=5432
readonly POSTGRES_USERNAME=instanaadmin
# readonly POSTGRES_PASSWORD=RKMzpHoEAn76f6nm3OSBu5fjNql1df

backup_pg_db() {
  dbname="$1"
  echo "$POSTGRES_HOST:$POSTGRES_PORT:$dbname:$POSTGRES_USERNAME:$POSTGRES_PASSWORD" > "$pg_passfile"
  chmod go-rwx "$pg_passfile"
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  pg_dump -F c -f "$backup_folder/${dbname}_$TIMESTAMP.dmp"  -C -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME "$dbname"
  cp "$backup_folder/${dbname}_$TIMESTAMP.dmp" "$backup_folder/$dbname.dmp"
  rm -rf "${backup_folder}/${dbname}_${TIMESTAMP}.dmp"
  return $?
}

restore_pg_db() {
  dbname="$1"
  echo "$POSTGRES_HOST:$POSTGRES_PORT:$dbname:$POSTGRES_USERNAME:$POSTGRES_PASSWORD" > "$pg_passfile"
  chmod go-rwx "$pg_passfile"
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  pg_restore -F c -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USERNAME" -d "$dbname" -c -O "$backup_folder/${dbname}.dmp"
  return $?
}

main() {
    type="$1"
    POSTGRES_PASSWORD="$2"

    dblist=("butlerdb" "instanaadmin" "sales" "tenantdb")

    backup_folder=$(dirname "$0")
    pg_passfile="$backup_folder/passfile"
    export PGPASSFILE="$pg_passfile"


    if [ "$type" == "backup" ]; then
        echo "backing up db"
        for db in "${dblist[@]}"; do
            echo "  $db"
            backup_pg_db "$db"
        done

        result=$?
        if  [ "$result" == "0" ]; then
        echo "Backup database success"
        else
        echo "Backup database failed"
        fi
        exit $result
    elif [ "$type" == "restore" ]; then
        echo "restoring db from backup"
        for db in "${dblist[@]}"; do
            echo "  $db"
            restore_pg_db "$db"
        done

        result=$?
        if  [ "$result" == "0" ]; then
            echo "Restore database success."
        else
            echo "Restore database failed."
        fi
        exit $result
    else
        echo "parameter error"
        exit 1
    fi
}

main "$@"