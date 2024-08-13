#!/usr/bin/env bash
#
# © Copyright IBM Corp. 2024
# 
# 
#
#shellcheck source=/dev/null
source cassandra-utils.sh

echo "[INFO] $(date) Updating the nodetool command"
cassandnodes=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running  --no-headers=true --output=custom-columns=NAME:.metadata.name | grep "instana-cassandra-default-sts-[0-9]")
for pod in $cassandnodes; do
  kubectl cp -n "$namespace" cassandra_functions.sh "$pod":/opt/cassandra/backup_scripts/cassandra_functions.sh
done
