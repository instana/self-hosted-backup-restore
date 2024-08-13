#!/usr/bin/env bash
#
# © Copyright IBM Corp. 2024
# 
# 
#

#shellcheck source=/dev/null
source cassandra-utils.sh

cassandnodes=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running  --no-headers=true --output=custom-columns=NAME:.metadata.name | grep "instana-cassandra-default-sts-[0-9]")
for pod in $cassandnodes; do
  kubectl exec "$pod" -n "$namespace" -- bash -c "mkdir -p /opt/cassandra/backup_scripts"
  kubectl cp -n "$namespace" ../backup_scripts/cassandra_functions.sh "$pod":/opt/cassandra/backup_scripts/cassandra_functions.sh
  kubectl cp -n "$namespace" ../backup_scripts/backup_cassandra.sh "$pod":/opt/cassandra/backup_scripts/backup_cassandra.sh
  kubectl cp -n "$namespace" ../backup_scripts/cassandra.env "$pod":/opt/cassandra/backup_scripts/cassandra.env
  kubectl cp -n "$namespace" ../backup_scripts/restore_cassandra.sh "$pod":/opt/cassandra/backup_scripts/restore_cassandra.sh
done

cassandraextrapod=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running  --no-headers=true --output=custom-columns=NAME:.metadata.name | grep "instana-cassandra-default-sts-[1-9]")

if [ -n "$cassandraextrapod" ]; then
  echo "[INFO] $(date) This is multinode cassandra cluster, hence updating the cassandra_functions.sh for other nodes"
    
  #update the cassandra_functions.sh for restore operation and then copying it to other pods of Cassandra in HA cluster
  echo "[INFO] $(date) Updating and copying the cassandra_functions.sh to other Cassandra pods in HA cluster"
  kubectl cp -n "$namespace" instana-cassandra-default-sts-0:/opt/cassandra/backup_scripts/cassandra_functions.sh /tmp/cassandra_functions.sh
  sed -zi 's/truncate_all_tables/#truncate_all_tables/2'  /tmp/cassandra_functions.sh
  sed -zi 's/test_result $? "truncate tables"/#test_result $? "truncate tables"/'  /tmp/cassandra_functions.sh

  #Copy the updated cassandra_functions.sh to other cassandra nodes except first one
  for pod in $cassandraextrapod; do
    kubectl cp -n "$namespace"  /tmp/cassandra_functions.sh "$pod":/opt/cassandra/backup_scripts/cassandra_functions.sh
  done
else
  echo "[INFO] $(date) This is single node Cassandra cluster, so no need to update cassandra_functions.sh"
fi

