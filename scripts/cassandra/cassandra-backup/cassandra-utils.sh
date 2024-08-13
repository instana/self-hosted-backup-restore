#!/usr/bin/env bash
#
# © Copyright IBM Corp. 2024
# 
# 
#

namespace=$(jq -r '.cassandraNamespace' < instana-config.json)
#echo $namespace

kpodloop() {
  pod_pattern=$1
  pod_command=$2
  pod_list=$( kubectl get pods -n "$namespace"  --field-selector=status.phase=Running --no-headers=true --output=custom-columns=NAME:.metadata.name | grep "$pod_pattern" )
  printf "Pods found: %s\n" "$(echo -n "${pod_list}")"
  for pod in $pod_list; do
    printf "\n===== EXECUTING COMMAND in pod: %-42s =====\n" "$pod"
    kubectl exec "$pod" -n "$namespace"  -- bash -c "$pod_command"
    printf '_%.0s' {1..80}
    printf "\n"
  done;
}
