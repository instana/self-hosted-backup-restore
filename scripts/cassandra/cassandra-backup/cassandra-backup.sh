#!/usr/bin/env bash
#
# © Copyright IBM Corp. 2024
# 
# 
#

set -o errexit
set -o pipefail
set -o nounset

echo "[INFO] $(date) ############## Cassandra backup started ##############"

basedir=$(dirname "$0")
cd "$basedir" || exit
current=$(pwd)
echo "$current"

# shellcheck source=/dev/null
source cassandra-utils.sh

#Run a cleanup on all keyspaces in all Cassandra instances
echo "[INFO] $(date) Running the cleanup on all keyspaces in all Cassandra instances"
keyspaces=$(jq .keyspaces[].name < cassandra-keyspace.json)
for k in $keyspaces; do
  echo "[INFO] $(date) Cleaning on the keyspace $k"
  kpodloop instana-cassandra-default-sts-[0-9] "nodetool -Dcom.sun.jndi.rmiURLParsing=legacy cleanup $k"
done

echo "[WARNING] $(date) Deleting the previous backups from Cassandra pods"
cassandnodes=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running  --no-headers=true --output=custom-columns=NAME:.metadata.name | grep "instana-cassandra-default-sts-[0-9]")
for pod in $cassandnodes; do
  kubectl exec "$pod" -n "$namespace" -- bash -c "mkdir -p /opt/cassandra/backup_scripts"
  kubectl exec "$pod" -n "$namespace" -- bash -c "rm -rf /var/lib/cassandra/backup_tar/*"
  kubectl cp -n "$namespace" ../backup_scripts/cassandra_functions.sh "$pod":/opt/cassandra/backup_scripts/cassandra_functions.sh
  kubectl cp -n "$namespace" ../backup_scripts/backup_cassandra.sh "$pod":/opt/cassandra/backup_scripts/backup_cassandra.sh
  kubectl cp -n "$namespace" ../backup_scripts/cassandra.env "$pod":/opt/cassandra/backup_scripts/cassandra.env
  kubectl cp -n "$namespace" ../backup_scripts/restore_cassandra.sh "$pod":/opt/cassandra/backup_scripts/restore_cassandra.sh
done

# Trigger backup: run backup on all Cassandra instances
./trigger-cassandra-backup.sh

# Creating a configmap to store the timestamp for backup tar file name
replicas=$(kubectl get sts instana-cassandra-default-sts -n "$namespace" -o jsonpath='{.spec.replicas}')

index=0
map_file_path="/tmp/cassandra-config-data-map.json"
json="{}"

# Removing file before creation
rm -f $map_file_path

while [ "$index" -lt "$replicas" ]; do
  pod_name+="instana-cassandra-default-sts-"
  pod_name+="$index"

  backup_tarfile=$(kubectl exec "$pod_name" -n "$namespace" -- bash -c "ls /var/lib/cassandra/backup_tar -rt | tail -1")
  if [ -z "$backup_tarfile" ]; then
    echo "[ERROR] $(date) No backup tar file is created for Cassandra, hence exiting!"
    #./post-cassandra-backup.sh
    exit 1
  else
    echo "[INFO] $(date) Backup tar $backup_tarfile file is created successfully!"
  fi

  backup_timestamp=$(echo "$backup_tarfile" | grep -oP '[\d]+-[\d]+-[\d]+-[\d]+-[\d]+')
  if [ $? -eq 0 ]; then
    echo "[INFO] $(date) Backup timestamp for Cassandra is $backup_timestamp"
  else
    echo "[ERROR] $(date) Unable to retrieve backup timestamp, hence exiting!"
    exit 1
  fi

  json=$(jq --arg t "$backup_timestamp" --arg p "$pod_name" '. + {($p): $t}' <<<"$json")
  index=$((index + 1))

  pod_name=""
done

echo "$json" > $map_file_path

echo "[INFO] $(date) Creating a configmap to store the timestamp for backup tar file name"
kubectl delete configmap cassandra-bcdr-config -n "$namespace" 2> /dev/null || true
kubectl create configmap cassandra-bcdr-config --from-file=$map_file_path -n "$namespace"

# Deleting a temp file as it is not needed
rm -f $map_file_path

echo "[INFO] $(date) ############## Cassandra backup completed ##############"
