#!/bin/bash
#
# © Copyright IBM Corp. 2024
# 
# 
#

#shellcheck source=/dev/null
source cassandra-utils.sh

cassandrarestore(){    
  cassandra_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running  --no-headers=true --output=custom-columns=NAME:.metadata.name | grep "instana-cassandra-default-sts-[0-9]")
  keyspaces=$(jq .keyspaces[].name < cassandra-keyspace.json)

  pod_timestamp_map=$(kubectl get cm cassandra-bcdr-config -o jsonpath='{.data.cassandra-config-data-map\.json}' -n "$namespace")
  echo "[INFO] $(date) Cassandra Pods and Backup timestamp map: $pod_timestamp_map"

  ## get cassandra username and password from secret
  cassandra_user=$(kubectl get secret instana-superuser  -o jsonpath='{.data.username}'|base64 -d)
  cassandra_pass=$(kubectl get secret instana-superuser  -o jsonpath='{.data.password}'|base64 -d)

  restore_check_value=0
  for keyspace in $keyspaces; do
    if [ $restore_check_value -ne 0 ]; then
      break
    fi
    for pod in $cassandra_pods; do
      # Retrieving backup timestamp from cassandra-bcdr-config configmap
      backup_timestamp=$(jq -r --arg k "$pod" '.[$k]' <<< "$pod_timestamp_map")
      echo "[INFO] $(date) Restoring the keyspace $keyspace on pod $pod"
      kpodloop "$pod" "/opt/cassandra/backup_scripts/restore_cassandra.sh -k $keyspace  -t $backup_timestamp -u ${cassandra_user} -p ${cassandra_pass} -f"
      if [ $? -ne 0 ]; then
        echo "[ERROR] $(date) Failed to restore keyspace $keyspace on pod $pod, hence aborting the Cassandra restore operation"
        restore_check_value=1
	    break
      fi
    done
  done
}

cassandrarestore
