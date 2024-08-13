#!/usr/bin/env bash
#
# © Copyright IBM Corp. 2024
# 
# 
#
#shellcheck source=/dev/null
source cassandra-utils.sh

pbkc() {
  ## Parallel Backup of Kubernetes Cassandra
  DATE=$( date +"%F-%H-%M-%S" )
  logfile_base=/tmp/clusteredCassandraBackup-${DATE}-
  declare -A pidwait
  declare -A log
  ## get cassandra username and password from secret 
  cassandra_user=$(kubectl get secret instana-superuser  -o jsonpath='{.data.username}'|base64 -d)
  cassandra_pass=$(kubectl get secret instana-superuser  -o jsonpath='{.data.password}'|base64 -d)
  ## get the current list of cassandra pods.
  podlist=$( kubectl get pods -n "$namespace" --field-selector=status.phase=Running  --no-headers=true --output=custom-columns=NAME:.metadata.name | grep "instana-cassandra-default-sts-[0-9]" )
  for pod in ${podlist}; do
    log[$pod]=${logfile_base}${pod}.log
    echo -e "BACKING UP CASSANDRA IN POD $pod (logged to ${log[$pod]})"
    kubectl exec "$pod" -n "$namespace" -- bash -c "/opt/cassandra/backup_scripts/backup_cassandra.sh  -u $cassandra_user -p $cassandra_pass -f" > "${log[$pod]}" & pidwait[$pod]=$!
  done

  echo -e "${#pidwait[@]} Cassandra backup is in progress ..."

  for pod in $podlist; do
    wait "${pidwait[$pod]}"
    echo -e "Backup of $pod completed, please verify via log file (${log[$pod]})"
  done
}

pbkc
