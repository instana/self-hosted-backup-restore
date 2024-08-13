#!/usr/bin/env bash

readonly NS=instana-postgres
# timeout=900
# interval=60
readonly TIMEOUT_CR=60
readonly TIMEOUT_PODCOUNT=300
readonly TIMEOUT_RESTIC=1200
readonly INTERVAL_RESTIC=60

global_replica_count=0
velero_cmd='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'

wait_cnpg_operator_eady() {
  ## Wait postgres pod to Ready
  local return_result=0

  kubectl get pod -n ${NS} |grep "cnpg-cloudnative-pg-"|awk '{print $1}' |
    while read -r pod; do
      kubectl -n ${NS} wait pod/"${pod}" --for=condition=Ready --timeout=60s
      return_result=$?
      if [[ ${return_result} -ne 0 ]]; then
          echo "cnpg operator pod not ready, restarting."
          kubectl -n ${NS} delete "pod/${pod}"
          sleep 3
          kubectl -n ${NS} wait pod/"${pod}" --for=condition=Ready --timeout=60s
          return 0
      else
        return 0
      fi
    done
}

wait_postgres_pods_ready() {
  ## Wait postgres pod to Ready, set timeout with parm
  local timeout_ready="$1"
  local ready_result=0

  kubectl get pod -n ${NS} |grep "postgres-"|awk '{print $1}' |
    while IFS="" read -r pod; do 
      kubectl -n ${NS} wait "pod/${pod}" --for=condition=Ready --timeout="${timeout_ready}s"
      ready_result=$?
      if [[ ${ready_result} -ne 0 ]]; then echo "pod/${pod} not ready."; exit 1; fi
    done
  ready_result=$?
  if [[ ${ready_result} -ne 0 ]]; then return 1; fi
  return 0
}

wait_cluster_cr() {
  timeout_cr=${TIMEOUT_CR}
  echo "Checking clusters.postgresql.cnpg.io CR"
  while true; do
    # result=`kubectl -n ${NS} get clusters.postgresql.cnpg.io  postgres|grep -q 'not found'`
    result=$(kubectl -n ${NS} get clusters.postgresql.cnpg.io postgres 2>&1)
    if ! (echo "${result}"|grep -q 'not found'); then break; fi

    ((timeout_cr=timeout_cr-5))
    if [[ ${timeout_cr} -le 0 ]]; then 
      echo "CR clusters.postgresql.cnpg.io/postgres check timeout, abort."
      return 1
    fi  
    sleep 5
  done

  global_replica_count=$(kubectl -n ${NS} get clusters.postgresql.cnpg.io postgres -ojsonpath="{.spec.instances}")
  echo "clusters.postgresql.cnpg.io CR checked"
  return 0
}

wait_postgres_pods_scheduled() {
  ## Wait postgres pod to be scheduled
  local timeout_podcount=${TIMEOUT_PODCOUNT}
  while true; do
    podcount=$(kubectl get pod -n ${NS} |grep -c "postgres-")
    if [ "${global_replica_count}" -le "${podcount}" ];then echo "all postgres replica pod scheduled"; break; fi

    if [ "${timeout_podcount}" -le 0  ];then echo "timeout, abort"; exit 1; fi
    ((timeout_podcount=timeout_podcount-10))
    echo "waiting for pods to be scheduled"
    sleep 10
  done
}

wait_restic_restore_complete() {
  local return_result=0
  local timeout_restic=${TIMEOUT_RESTIC}
  kubectl get pod -n ${NS} |grep "postgres-"|awk '{print $1}' |
    while IFS="" read -r pod; do 
      echo "$pod"
      while true; do
        restic_result=$(kubectl logs "${pod}" -n "${NS}" -c restore-wait --tail=100 2>&1| grep 'restic restores are done')
        if [[ "${restic_result}" ]]; then
          echo "${pod} restic restore completed"
          break
        else
          echo "the ${pod} restic restore is not completed yet"
          ((timeout_restic=timeout_restic-INTERVAL_RESTIC))
          if [ "${timeout_restic}" -le 0 ]; then
            echo "timeout waiting pod ${pod} to be ready."
            exit 1
          fi
          sleep ${INTERVAL_RESTIC}
        fi
      done
    done 
  return_result=$?
  if [ "${return_result}" -ne 0 ]; then return 1; fi
  return 0
}

restore_from_backup() {
  # local readyresult=0
  echo "restoring Postgres from backup $1"
  $velero_cmd restore create \
    --from-backup "$1" \
    --include-namespaces instana-postgres \
    --include-cluster-resources=true \
    --wait
  wait_cnpg_operator_eady

  echo "restoring Postgres CR from backup $1"
  $velero_cmd restore create \
    --from-backup "$1" \
    --include-resources clusters.postgresql.cnpg.io \
    --wait
  exit 0
}

main() {
  if [ "$#" -ne 1 ]; then
    echo "need to provide 1 parm for Postgres password."
    exit 1
  fi

  POSTGRES_PASSWORD=$1
  # BACKUP_NAME=$1
  result=0
  script_folder=$(dirname "$0")
  # restore_from_backup $BACKUP_NAME
  # result=$?
  # if [[ ${result} -ne 0 ]]; then echo "cnpg operator pod not ready timeout, abort"; exit 1; fi

  wait_cluster_cr
  result=$?
  if [[ ${result} -ne 0 ]]; then echo "CR not found, abort."; exit 1; fi

  wait_postgres_pods_scheduled

  wait_postgres_pods_ready 3
  result=$?
  if [[ ${result} -ne 0 ]]; then 
    wait_restic_restore_complete
    result=$?
    if [[ ${result} -ne 0 ]]; then echo "Restic restore timeout, abort."; exit 1; fi
    # restart postgres 
    kubectl get pod -n ${NS} |grep "postgres-"|awk '{print $1}'|xargs kubectl -n ${NS} delete pod

    ## Wait postgres pod to start
    while true; do 
      podcount=$(kubectl get pod -n ${NS} |grep -c "postgres-")
      if [ "${global_replica_count}" -eq "${podcount}" ];then break; fi
      echo "waiting for postgres pods to start"
      sleep 10
    done  
  fi

  ## Wait postgres pod to Ready
  wait_postgres_pods_ready 300
  # podlist=( $(kubectl get pod -n ${NS} |grep "postgres-"|awk '{print $1}') )
  # for pod in "${podlist[@]}"; do
  #   kubectl -n ${NS} wait "pod/${pod}" --for=condition=Ready --timeout=300s
  # done

  pod=$(kubectl -n ${NS} get pod -l cnpg.io/instanceRole=primary|grep -v NAME|awk '{print $1}')
  if echo "${pod}" | grep -q "No resources found"; then
    echo "Could not found Postgres master node."
    exit 1
  else
    echo "copy pg_db_bk_rst.sh to pod: ${pod}"
    oc cp "${script_folder}"/pg_db_bk_rst.sh "${pod}:/var/lib/postgresql/data" -c postgres -n ${NS}
    echo "restoring databases"
    oc exec -i -t "${pod}" -c postgres -n "${NS}"  -- /var/lib/postgresql/data/pg_db_bk_rst.sh restore "${POSTGRES_PASSWORD}"
  fi
}

main "$@"

