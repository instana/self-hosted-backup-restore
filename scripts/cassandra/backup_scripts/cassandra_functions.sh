#!/usr/bin/env bash

#
#IBM Confidential
#5737-M96
#Copyright IBM Corp. 2014, 2024
#

set -o errexit
set -o pipefail
set -o nounset

##set global env variables for both back and restore scripts
TAR_SPEED_LIMIT=${CASSANDRA_BACKUP_SPEED:=17M}
USER="${CASSANDRA_USER:-cassandra}"
PASS="${CASSANDRA_PASS:-cassandra}"
TODAY_DATE=$(date +%F)

DATE_TIME=$(date +%F-%H%M-%S)
SNAPSHOT_NAME=snp-${DATE_TIME}

SCRIPT_NAME=$(basename "$0")
TIMESTAMP=$(date +%Y%m%d%H%M)
CASSANDRA_CLIENT_ENCRYPTION_ENABLED="false"
#if [ ! "${LOG_PATH}" = "" ] ; then
#  SCRIPT_LOG=${LOG_PATH}/${SCRIPT_NAME}-${TIMESTAMP}.log
#else
#  SCRIPT_LOG=/tmp/${SCRIPT_NAME}-${TIMESTAMP}.log
#fi


test_result() {
 printf "%s RESULT=%s for %s \n" "$(date)" "$1" "$2"
 if [ $1 -ne 0 ]; then
    printf "%s FAILED in %s !!!!!!!!! \n" "$(date)" "$2"
    printf "%s ************************ \n" "$(date)"
    printf "%s  log file: %s \n" "$(date)" "$SCRIPT_LOG"
    exit 1;
 fi
}

####### Create / check backup Directory ####
create_dir() {
  dir="$1"
  new="$2"

  if [ -d  "$dir" ];then    
    if [ "$new" == "Y" ];then 
      printf "%s $dir already exist, removing it \n" "$(date)"
      rm -rf "$dir"
      test_result $? "rm -rf $dir"
    fi
  fi 
  mkdir -p "$dir"
  test_result $? "mkdir -p $dir"
  if [ "$(stat -c '%u' "$dir")" == "$(id -u)" ] || [ "$(id -nu)" == "root"  ];then
    chmod -R 775 "$dir"
    test_result $? "chmod -R 775 $dir"
  elif [ -w "$dir"  ];then
    printf "%s Permissions for %s cannot be modified but it is writable. Ignoring\n" "$(date)" "$dir"
  else
    printf "%s %s cannot be used for backup, directory is not writable. FAILED!!!!\n" "$(date)" "$dir"
    exit 1;
  fi
}


prepare() {
  ## Add -Dcom.sun.jndi.rmiURLParsing=legacy to work around stricter RMI validation in Java
  ## Should be removed when Cassandra is uplifted to 3.11.13
  ## Removed -Dcom.sun.jndi.rmiURLParsing=legacy for Cassandra is uplifted to 4.0.6
  nodetool="nodetool"
  printf "%s nodetool=%s \n" "$(date)" "$nodetool"
  if [ "$CASSANDRA_CLIENT_ENCRYPTION_ENABLED" = "true" ]; then
    cqlsh="cqlsh --ssl -u $USER -p $PASS"
    cqlsh_no_pass="cqlsh --ssl -u $USER -p XXXX"
  else
    cqlsh="cqlsh -u $USER -p $PASS"
    cqlsh_no_pass="cqlsh -u $USER -p XXXX"
  fi
  printf "%s cqlsh=%s \n" "$(date)" "$cqlsh_no_pass"
  cassandra_server=$($nodetool describecluster |grep Name |awk  '{print $2}')
  printf "%s cassandra_server=$cassandra_server \n" "$(date)"
  get_all_keyspaces 
}

##### SCHEMA BACKUP
schema_backup() {
  printf "%s SCHEMA BACKUP \n" "$(date)"
  
  for ks in $keyspaces ;do
    printf "%s Take SCHEMA Backup for KEYSPACE %s \n" "$(date)" "$ks"
    $cqlsh -e "DESC KEYSPACE  ${ks}" > "${BACKUP_SCHEMA_DIR}/${ks}_schema-${DATE_TIME}.cql" 
    test_result $? "${cqlsh_no_pass} -e \"DESC KEYSPACE  ${ks}\" > ${BACKUP_SCHEMA_DIR}/${ks}_schema-${DATE_TIME}.cql"
  done
}

##### tokensnum file BACKUP
conf_backup(){
  printf "%d token file BACKUP \n" "$(date)"

  cp "$DATA_DIR/../tokensnum" "$BACKUP_CONF_DIR/tokensnum"
  test_result $? "cp ${DATA_DIR}/../tokensnum $BACKUP_CONF_DIR/tokensnum "
}

create_snapshots() {
  printf "%s Begin create_snapshots for keyspaces $keyspaces " "$(date)"
  for ks in $keyspaces ; do	
    printf "%s Creating snapshots for keyspace %s \n" "$(date)" "$ks"
    printf "%s %s snapshot -t %s %s \n" "$(date)" "$nodetool" "$SNAPSHOT_NAME" "$ks"

    $nodetool snapshot -t "$SNAPSHOT_NAME" "$ks" 
	test_result $? "$nodetool snapshot -t $SNAPSHOT_NAME $ks "
	
    #cd $DATA_DIR
    #test_result $? "cd $DATA_DIR"
    #tar -cf $BACKUP_SNAPSHOT_DIR/${ks}_${HOSTNAME}_${SNAPSHOT_NAME}.tar $ks/*/snapshots/$SNAPSHOT_NAME
    #test_result $? "tar -cf $BACKUP_SNAPSHOT_DIR/${ks}_${HOSTNAME}_${SNAPSHOT_NAME}.tar $ks/\*/snapshots/$SNAPSHOT_NAME"
  
    printf "%s Snapshot for keyspace %s copied in %s \n " "$(date)" "$ks" "$BACKUP_SNAPSHOT_DIR"
  done 
  
  
}

link_snapshots() {
  printf "%s Begin link_snapshots for keyspaces %s " "$(date)" "$keyspaces"
  for ks in $keyspaces ; do	
    printf "%s Linking snapshots for keyspace %s \n" "$(date)" "$ks"

    cd "$DATA_DIR" || exit
    test_result $? "cd $DATA_DIR"
	
    tables=$(ls "$ks"/)
	  for table in $tables ; do 
	    if [ -d "$DATA_DIR/$ks/$table/snapshots/$SNAPSHOT_NAME" ]; then
		    mkdir -p "$BACKUP_SNAPSHOT_DIR/$ks/$table/snapshots/"
		    test_result $? "mkdir -p $BACKUP_SNAPSHOT_DIR/$ks/$table/snapshots/"
		    printf "%s ln -s $DATA_DIR/$ks/$table/snapshots/$SNAPSHOT_NAME $BACKUP_SNAPSHOT_DIR/$ks/$table/snapshots/$SNAPSHOT_NAME" "$(date)"
		    ln -s "$DATA_DIR/$ks/$table/snapshots/$SNAPSHOT_NAME" "$BACKUP_SNAPSHOT_DIR/$ks/$table/snapshots/$SNAPSHOT_NAME"
		    test_result $? "ln -s $DATA_DIR/$ks/$table/snapshots/$SNAPSHOT_NAME $BACKUP_SNAPSHOT_DIR/$ks/$table/snapshots/$SNAPSHOT_NAME"
	    fi
	  done
  
    printf "%s Snapshot for keyspace %s copied in %s \n " "$(date)" "$ks" "$BACKUP_SNAPSHOT_DIR"
  done 

}

#
##### Clear existing snapshots
clear_snapshots() {
 for ks in $keyspaces ; do
  printf "%s Remove old snapshots no longer needed for keyspace %s \n" "$(date)" "$ks"
  $nodetool clearsnapshot "$ks" --all
 done 
}

get_all_keyspaces() {
  all_keyspaces_temp=$($cqlsh -e "DESC KEYSPACES" | sed 's/system_views//g' | sed 's/system_virtual_schema//g' | sed '/^\s*$/d' | awk '{gsub("\r"," ");print}') 
  test_result $? "$cqlsh_no_pass -e \"DESC KEYSPACES\" "
  count=0;
  all_keyspaces=""
  if [ -z "$all_keyspaces_temp" ]; then
    printf "%s #### No keyspace found !!! \n" "$(date)"
    return 1;
  else
    for ks in $all_keyspaces_temp; do
      if [ $count == 0 ]; then
        all_keyspaces="$ks"
      else
        all_keyspaces="$all_keyspaces $ks"
      fi
      count=$((count+1));
      printf "%s  KEYSPACE $count = $ks \n" "$(date)"
    done
  fi 
  printf "%s all_keyspaces=$all_keyspaces \n" "$(date)"
}

create_tar_file() { 
 cd "${BACKUP_TEMP_DIR}" || exit
 test_result $? "cd ${BACKUP_TEMP_DIR}"
 local keyspace=${keyspaces// /_KS_} 
 #local keyspace=$(echo "$keyspaces"|sed 's/ /_KS_/g')
 printf "%s keyspace=$keyspace \n" "$(date)"
 local cass_prefix="cassandra_"
 tar_file="${REMOTE_BACKUP_DIR}/${cass_prefix}${HOSTNAME}_KS_${keyspace}_date_${DATE_TIME}.tar"
 tar hcf - "$DATE_TIME" | pv -L "$TAR_SPEED_LIMIT" > "$tar_file"
 test_result $? "tar hcf - $DATE_TIME | pv -L $TAR_SPEED_LIMIT > $tar_file"
 
 
}

clean_backup_temp_dir() {
 rm -rf "$BACKUP_TEMP_DIR"
 test_result $? "rm -rf $BACKUP_TEMP_DIR"
} 

flush_keyspace(){
 $nodetool flush "$1"	
 test_result $? "$nodetool flush $1"
}

create_schema() {
 # Search if keyspace exist already 
 keyspace_found=1
 for ks in $all_keyspaces; do
    if [ "$ks" == "$KEYSPACE_TO_RESTORE" ]; then
       keyspace_found=0
    fi
 done    
 if [ $keyspace_found -eq 1 ]; then
   printf "%s keyspace %s does not exist, need to create it \n" "$(date)" "$KEYSPACE_TO_RESTORE"
   printf "%s find ${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SCHEMA -type f -name \"${KEYSPACE_TO_RESTORE}_schema-${SNAPSHOT_DATE_TO_RESTORE}.cql\" | wc -l \n" "$(date)"
   count=$(find "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SCHEMA" -type f -name "${KEYSPACE_TO_RESTORE}_schema-${SNAPSHOT_DATE_TO_RESTORE}.cql" | wc -l)
   if [ "$count" -eq 0 ]; then
     printf "%s There is no schema file for keyspace %s \n" "$(date)" "$KEYSPACE_TO_RESTORE"
     exit 1;
   else  
     printf "%s find ${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SCHEMA -type f -name \"${KEYSPACE_TO_RESTORE}_schema-${SNAPSHOT_DATE_TO_RESTORE}.cql\" \n" "$(date)"	   
     schema_cql_file=$(find "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SCHEMA" -type f -name "${KEYSPACE_TO_RESTORE}_schema-${SNAPSHOT_DATE_TO_RESTORE}.cql")
     
     create_dir "$CQL_PATH" "N"
     test_result $? "create_dir $CQL_PATH"
     cp "$schema_cql_file"  "$CQL_PATH" 
     test_result $? " cp $schema_cql_file  $CQL_PATH "
     basename_schema_cql_file=$(find "$schema_cql_file"|awk -F '/' '{print $(NF)}')
     printf "%s Schema for keyspace $KEYSPACE_TO_RESTORE must be created using cqlsh and file $basename_schema_cql_file located in $CQL_PATH \n" "$(date)"
     $cqlsh -f  "${CQL_PATH}/${basename_schema_cql_file}"
     test_result $? "$cqlsh_no_pass -f ${CQL_PATH}/${basename_schema_cql_file}"     
   fi  
 else
   printf "%s Schema exits ... continue... \n" "$(date)"  
 fi
}

get_cfstats() {
 prefix="$1"
 target_dir="$2"
 keyspace="$3"
 output_file1="${target_dir}/${prefix}_${HOSTNAME}_stats_${DATE_TIME}.log"
 
 if [ -z "$keyspace" ]; then
   printf "%s Taking statistics of Cassandra node \n" "$(date)"
 else
   printf "%s Taking statistics of Cassandra keyspace %s \n" "$(date)" "$keyspace"
   output_file2="${target_dir}/${keyspace}_keys.txt"
 fi	 

 $nodetool cfstats "$keyspace" > "${output_file1}"
 test_result $? "$nodetool cfstats $keyspace >  $output_file1"

 if [ -z "$output_file1" ] ;then
   printf "%s statistics on entire node ... nothing to do \n"	"$(date)"
 else
   create_key_result_file "$output_file1" "$output_file2"
   test_result $? "create_key_result_file $output_file1 $output_file2"
 fi
}

cleanup() {
 clean_backup_temp_dir 
}

create_key_result_file() {
 input_filename="$1"
 output_filename="$2"

 touch "$output_filename"
 test_result $? "touch $output_filename"
 printf "CASSANDRA DATA \n" > "$output_filename"
 if [ -f "$input_filename" ]; then
   while read -r line_w1 line_w2 line_w3 line_w4 line_end
   do
     if [ "$line_w1" == "Table:" ]; then
       printf "%s %s ; " "$line_w1" "$line_w2" >> "$output_filename"
     fi
     if [ "$line_w1" == "Number" ] && [ "$line_w3" == "keys" ]; then
       printf "keys=%s \n" "$line_end" >> "$output_filename"
     fi
   done  < "$input_filename"
 else
   printf "%s File %s does not exist \n" "$(date)" "$input_filename"
 fi
}

backup() {
 printf "%s \n Starting Backup \n" "$(date)"
    cleanup
    test_result $? "cleanup"

    prepare 
    
    if [ "$KEYSPACE_TO_BACKUP" == "ALL" ]; then
      keyspaces="$all_keyspaces"
    else
      keyspaces="$KEYSPACE_TO_BACKUP" 
    fi
    printf "%s keyspaces = %s \n" "$(date)" "$keyspaces"

    create_dir "$BACKUP_STATS_DIR" "N"
    test_result $? "create_dir $BACKUP_STATS_DIR" 

    for ks in $keyspaces ;do
      printf "%s ks=%s \n" "$(date)" "$ks"
      flush_keyspace "$ks"
      get_cfstats "$ks" "$BACKUP_STATS_DIR" "$ks"
    done 

    create_dir "$BACKUP_SCHEMA_DIR" "N"
    test_result $? "create_dir $BACKUP_SCHEMA_DIR"
    create_dir "$BACKUP_SNAPSHOT_DIR" "N"
    test_result $? "create_dir $BACKUP_SNAPSHOT_DIR" 
    create_dir "$BACKUP_CONF_DIR" "N"
    test_result $? "create_dir $BACKUP_CONF_DIR" 
    create_dir "$BACKUP_TEMP_DIR" "N"
    test_result $? "create_dir $BACKUP_TEMP_DIR"
    create_dir "$BACKUP_DIR" "N"
    test_result $? "create_dir $BACKUP_DIR"
     
    
    schema_backup 
    test_result $? "schema_backup"
    
    #conf_backup
    #test_result $? "conf_backup"

    clear_snapshots 
    create_snapshots 
    test_result $? "create_snapshots"
    
	link_snapshots
	
    create_tar_file 
    test_result $? "create_tar_file"

    printf "%s BACKUP DONE SUCCESSFULLY !!! \n\n" "$(date)"
    cleanup
    test_result $? "cleanup"
}

find_backup() {
  printf "%s SNAPSHOT_DATE_TO_RESTORE=%s \n" "$(date)" "$SNAPSHOT_DATE_TO_RESTORE"
   
  local cassandra_prefix="cassandra_"
  # Find the tar file for that cassandra server and that date
  if [ "$SNAPSHOT_DATE_TO_RESTORE" == "latest" ];then
     printf "%s Find latest snapshot for Keyspace: \"${KEYSPACE_TO_RESTORE}\" in  \"${REMOTE_BACKUP_DIR}\"\n" "$(date)"
     count=$(find "$REMOTE_BACKUP_DIR" -type f -name "${cassandra_prefix}${BACKUP_HOSTNAME}_KS_*${KEYSPACE_TO_RESTORE}*" |wc -l)
     if [ "$count" -eq 0 ]; then
       printf "%s Backup File not found \n" "$(date)"
       exit 1;
     else      
       printf "%s find $REMOTE_BACKUP_DIR -type f -name "${cassandra_prefix}${BACKUP_HOSTNAME}_KS_*${KEYSPACE_TO_RESTORE}*" -print0 |xargs -0 ls -ltr |tail -n 1 |awk -F '/' '{print \$(NF)}}' \n" "$(date)" 
       local file 
       file=$(find "$REMOTE_BACKUP_DIR" -type f -name "${cassandra_prefix}${BACKUP_HOSTNAME}_KS_*${KEYSPACE_TO_RESTORE}*" -print0 |xargs -0 ls -ltr |tail -n 1 |awk -F '/' '{print $(NF)}')
       tar_file=${REMOTE_BACKUP_DIR}/${file}
     fi
     
     SNAPSHOT_DATE_TO_RESTORE=$(echo "$tar_file"|sed 's/.*_date_//'|sed 's/\.tar//')       
  else
     local tar_file_search="${cassandra_prefix}${BACKUP_HOSTNAME}_*KS_${KEYSPACE_TO_RESTORE}*_date_${SNAPSHOT_DATE_TO_RESTORE}.tar"
     count=$(find "$REMOTE_BACKUP_DIR" -type f -name "$tar_file_search" |wc -l)
     if [ "$count" -eq 1 ]; then
       tar_file=$(find "$REMOTE_BACKUP_DIR" -type f -name "$tar_file_search")
     else
       printf "%s Backup file for Keyspace: \"${KEYSPACE_TO_RESTORE}\" for node \"${BACKUP_HOSTNAME}\" 
               for date \"${SNAPSHOT_DATE_TO_RESTORE}\" in \"${REMOTE_BACKUP_DIR}\" NOT FOUND ! \n" "$(date)"
       exit 1;
     fi  
  fi 
  printf "%s SNAPSHOT_DATE_TO_RESTORE=%s \n" "$(date)" "$SNAPSHOT_DATE_TO_RESTORE"
  printf "%s tar_file=%s \n" "$(date)" "$tar_file"
}

truncate_all_tables() {
 $cqlsh -e "SELECT table_name FROM system_schema.tables WHERE keyspace_name = '$KEYSPACE_TO_RESTORE'" \
  | sed -e '1,/^-/d' -e '/^(/d' -e '/^$/d' \
  | while read -r TAB; do
    printf "%s Truncate table %s \n" "$(date)" "$TAB"
    $cqlsh -e "TRUNCATE $KEYSPACE_TO_RESTORE.$TAB"
    test_result $? "$cqlsh_no_pass -e \"TRUNCATE $KEYSPACE_TO_RESTORE.$TAB\""
 done
}

repair_keyspace() {
 $nodetool repair -full -seq "${KEYSPACE_TO_RESTORE}"
}

clear_commit_log() {
  printf "%s Clear Commit Logs \n" "$(date)"
  rm -rf "${DATA_DIR}/../commitlog/*"
  test_result $? "rm -rf ${DATA_DIR}/../commitlog/*"    
}

extract_tarfile() {  
  cd "$BACKUP_TEMP_DIR" || exit
  test_result $? "cd $BACKUP_TEMP_DIR"
    
  #--no-same-owner --no-same-permissions needed for if you're extracting onto a mounted dir without root permissions
  printf "%s untar file %s \n" "$(date)" "$tar_file"
  tar -xf "$tar_file" --no-same-owner --no-same-permissions
  test_result $? "tar -xf ${tar_file} --no-same-owner --no-same-permissions"
}

sstableloader_tables() {
  printf "%s  Now trying to load snapshot tar file %s \n" "$(date)" "$snapshot_tarfile"
  SNAPSHOT_NAME="snp-${SNAPSHOT_DATE_TO_RESTORE}" 
  
  tables=$($nodetool cfstats "$KEYSPACE_TO_RESTORE" | grep "Table: " | sed -e 's+^.*: ++')
  for table in $tables; do
    echo "Loading table $table"
    cd "${DATA_DIR}/${KEYSPACE_TO_RESTORE}/${table}-*"
    test_result $? "cd ${DATA_DIR}/${KEYSPACE_TO_RESTORE}/${table}-*"
	printf "ls -ltr %s\n" "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/snapshots/${SNAPSHOT_NAME}/"
	ls -ltr "${BACKUP_TEMP_DIR}"/"${SNAPSHOT_DATE_TO_RESTORE}"/SNAPSHOTS/"${KEYSPACE_TO_RESTORE}"/"${table}"-*/snapshots/"${SNAPSHOT_NAME}"/
    if [ "$(find "${BACKUP_TEMP_DIR}"/"${SNAPSHOT_DATE_TO_RESTORE}"/SNAPSHOTS/"${KEYSPACE_TO_RESTORE}"/"${table}"-*/snapshots/"${SNAPSHOT_NAME}"/ | wc -l)" -gt '0' ]; then
		mv "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/snapshots/${SNAPSHOT_NAME}/*" "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/"
		test_result $? "mv ${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/snapshots/${SNAPSHOT_NAME}/* ${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/"
		
		sstableloader -u "$USER" -pw "$PASS" -d "$CASSANDRA_IP ${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/"
		test_result $? "sstableloader -d $CASSANDRA_IP ${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/"
		
        echo "    Table $table loaded."
    else
        echo "    >>> Nothing to loaded."
    fi   
    cd "$DATA_DIR"
    test_result $? "cd $DATA_DIR"
  done
  
}
 
restore_and_refresh_tables() { 
  SNAPSHOT_NAME="snp-${SNAPSHOT_DATE_TO_RESTORE}" 

  tables=$($nodetool cfstats "$KEYSPACE_TO_RESTORE" | grep "Table: " | sed -e 's+^.*: ++')
  for table in $tables; do
    echo "Restore table ${table}"
    ID=$($cqlsh -e "select id from system_schema.tables WHERE keyspace_name='$KEYSPACE_TO_RESTORE' and table_name='$table'"|grep -Evw "id|rows"|grep -v "\-\-\-"|grep .|sed s/" "*//g|sed s/"-"//g)
    test_result $? "$cqlsh_no_pass -e \"select id from system_schema.tables WHERE keyspace_name='$KEYSPACE_TO_RESTORE' and table_name='$table'\""
    table_dir="${table}-${ID}"
    if [ ! -d "${DATA_DIR}/${KEYSPACE_TO_RESTORE}/${table_dir}" ]; then
      echo "Directory $table_dir not found for $table in ${DATA_DIR}/${KEYSPACE_TO_RESTORE}/"
      echo "ls ${DATA_DIR}/${KEYSPACE_TO_RESTORE}/"
      ls "${DATA_DIR}/${KEYSPACE_TO_RESTORE}/"
      echo
    else
      cd "${DATA_DIR}/${KEYSPACE_TO_RESTORE}/${table_dir}"
      test_result $? "cd ${DATA_DIR}/${KEYSPACE_TO_RESTORE}/$table_dir"
      printf "ls -ltr %s\n" "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/snapshots/${SNAPSHOT_NAME}/"
      ls -ltr "${BACKUP_TEMP_DIR}"/"${SNAPSHOT_DATE_TO_RESTORE}"/SNAPSHOTS/"${KEYSPACE_TO_RESTORE}"/"${table}"-*/snapshots/"${SNAPSHOT_NAME}"/
      if [ "$(find "${BACKUP_TEMP_DIR}"/"${SNAPSHOT_DATE_TO_RESTORE}"/SNAPSHOTS/"${KEYSPACE_TO_RESTORE}"/"${table}"-*/snapshots/"${SNAPSHOT_NAME}"/ | wc -l)" -gt '0' ]; then
        $nodetool import "$KEYSPACE_TO_RESTORE" "$table" "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/snapshots/${SNAPSHOT_NAME}"
        test_result $? "$nodetool import $KEYSPACE_TO_RESTORE $table ${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/SNAPSHOTS/${KEYSPACE_TO_RESTORE}/${table}-*/snapshots/${SNAPSHOT_NAME}"
        echo "    Table $table restored."
      else
        echo "    >>> Nothing to restore."
      fi
    fi
    cd "$DATA_DIR"
    test_result $? "cd $DATA_DIR"
  done
}

check_restore() {
  restored_file="${BACKUP_STATS_DIR}/${KEYSPACE_TO_RESTORE}_keys.txt" # after_restore
  expected_file="${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/STATS/${KEYSPACE_TO_RESTORE}_keys.txt" # in restore tar file, expected

  printf "%s Comparing $restored_file to $expected_file\n" "$(date)"
  diff_result=$(diff -s "$restored_file" "$expected_file"|grep -c "identical")

  printf "%s \nEXPECTING: \n" "$(date)"
  cat "$expected_file"
  printf "%s \nRESTORED: \n" "$(date)"
  cat "$restored_file"

  if [ "$diff_result" -ne 1 ]; then
    printf "%s \nKeyspace not containing the number of keys expected \n" "$(date)"
    exit 1;
  else
    printf "%s \nFiles are identical. Restore successful!!! \n" "$(date)"
  fi
}

restore() {

  cleanup
  prepare

  create_dir "$BACKUP_TEMP_DIR" "N"
  test_result $? "create_dir $BACKUP_TEMP_DIR"

  find_backup 
  test_result $? "find backup"

  extract_tarfile 
  test_result $? "extract_tarfile"

  create_schema
  test_result $? "create Schema"

  create_dir "$BACKUP_STATS_DIR" "N"
  test_result $? "create_dir $BACKUP_STATS_DIR" 
  get_cfstats "before_restore" "$BACKUP_STATS_DIR" "$KEYSPACE_TO_RESTORE"
  test_result $? "get_cfstats \"before_restore\" $BACKUP_STATS_DIR $KEYSPACE_TO_RESTORE"  

  printf "%s Starting Restore \n" "$(date)"

  truncate_all_tables
  test_result $? "truncate tables"  

  repair_keyspace
  test_result $? "repair keyspace"

  clear_commit_log 
  test_result $? "clear_commit_log"

  restore_and_refresh_tables
  test_result $? "restore_and_refresh_tables"

  get_cfstats "after_restore" "$BACKUP_STATS_DIR" "$KEYSPACE_TO_RESTORE"
  test_result $? "get_cfstats \"after_restore\" $BACKUP_STATS_DIR $KEYSPACE_TO_RESTORE"

  check_restore

  cleanup
  test_result $? "cleanup"

  printf "%s RESTORE DONE !!!\n\n" "$(date)"
}

restore_sstableloader() {
  printf "%s RESTORING WITH SSTABLELOADER" "$(date)"
  
  cleanup
  prepare

  create_dir "$BACKUP_TEMP_DIR" "N"
  test_result $? "create_dir $BACKUP_TEMP_DIR"

  find_backup 
  test_result $? "find backup"

  extract_tarfile 
  test_result $? "extract_tarfile"  
  
  create_schema
  test_result $? "create Schema"
  
  create_dir "$BACKUP_STATS_DIR" "N"
  test_result $? "create_dir $BACKUP_STATS_DIR" 
  get_cfstats "before_restore" "$BACKUP_STATS_DIR" "$KEYSPACE_TO_RESTORE"
  test_result $? "get_cfstats \"before_restore\" $BACKUP_STATS_DIR $KEYSPACE_TO_RESTORE"  
  
  printf "%s Starting Restore \n" "$(date)"
  sstableloader_tables
  test_result $? "sstableloader_tables" 
  
  get_cfstats "after_restore" "$BACKUP_STATS_DIR" "$KEYSPACE_TO_RESTORE"
  test_result $? "get_cfstats \"after_restore\" $BACKUP_STATS_DIR $KEYSPACE_TO_RESTORE"

  check_restore

  cleanup
  test_result $? "cleanup"

  printf "%s RESTORE DONE !!!\n\n" "$(date)"
  
}

test_force() {
 if [ "$FORCE" == "Y" ]; then
   ok=0
 else
   printf "%s ************************************ \n" "$(date)"
   printf "%s  Do you want to continue (y/n) ? \n" "$(date)"
   read -r ans

   #ans=$(tr '[:upper:]' '[:lower:]'<<<$ans)
   ok=1

   if [[ "$ans" == "y"  ||  "$ans" == "yes"  ]]; then
     ok=0
   fi
 fi

 test_result $ok "Read answer" 
}

check_tokennums() {
  if [ "${IGNORE_CHECK}" == "Y" ]; then
    printf "%s Skip token number check for -i parameter is added \n" "$(date)"
    return
  fi
  printf "%s Checking number of tokens in backup and restore environment \n" "$(date)"
  
  backup_token=$(cat "${BACKUP_TEMP_DIR}/${SNAPSHOT_DATE_TO_RESTORE}/CONF/tokensnum")
  if [ $? -ne 0 ]; then
    printf "%s The tokensnum file can't be found in backup file. There may be risk if token numbers don't match in backup and restore environments, suggest to check token number manually. Use -i parameter to skip this check if you want to continue \n" "$(date)"
    result=1
  else
    result=0
  fi

  test_result $result "Check tokensnum file in the backup environment"

  restore_token=$(cat "${DATA_DIR}/../tokensnum")
  if [ $? -ne 0 ]; then
    printf "%s The tokensnum file can't be found in restore environment. There may be risk if token numbers don't match in backup and restore environments, suggest to check token number manually. Use -i parameter to skip this check if you want to continue \n" "$(date)"
    result=1
  else
    result=0
  fi
  test_result $result "Check tokensnum file in the restore environment"

  if [ "$backup_token" == "$restore_token" ]; then
    result=0
  else
    printf "%s The token number in backup environment: %s, in restore environment: %s \n" "$(date)" "$backup_token" "$restore_token"
    printf "%s There may be risk if token numbers don't match in backup and restore environments. If you want to continue the restore even token numbers don't match, pls use -i parameter to restore. \n" "$(date)"
    result=1
  fi
  test_result $result "Check token numbers in backup and restore environments are same"
}
