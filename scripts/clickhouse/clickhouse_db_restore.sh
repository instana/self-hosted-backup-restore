#!/usr/bin/env bash

readonly CH_RESTORE_TIMEOUT=3600 # Increase this number if clickhouse have large amount of data.
readonly NS=instana-clickhouse

GLOBAL_TIMEOUT_PODCOUNT=60

wait4ClickhousePodsStart() {
  ## Wait postgres pod to start
  local replicaCount=0
  local timeout_podcount=GLOBAL_TIMEOUT_PODCOUNT
  replicaCount=$(kubectl -n "${NS}" get clickhouseinstallations.clickhouse.altinity.com instana -ojsonpath="{.spec.configuration.clusters[0].layout.replicasCount}")
  local result=$?
  if [[ ${result} -ne 0 ]]; then echo "Clickhouse CR error, abort."; exit 1; fi

  while true 
  do
    podcount=$(kubectl get pod -n "${NS}" |grep -c "chi-instana-local-")
    if [ "${replicaCount}" -le "${podcount}" ];then echo "all clickhouse replica pod scheduled"; break; fi

    if [ "${timeout_podcount}" -le 0  ];then echo "timeout, abort"; exit 1; fi
    ((timeout_podcount=timeout_podcount-10))
    echo "waiting for pods to be scheduled"
    sleep 10
  done
}

wait4ZookeeperPodsStart() {
  local replicaCount=0
  local timeout_podcount=GLOBAL_TIMEOUT_PODCOUNT

  replicaCount=$(kubectl -n "${NS}" get zookeeperclusters.zookeeper.pravega.io  instana-zookeeper -ojsonpath="{.spec.replicas}")
  
  while true 
  do
    podcount=$(kubectl get pod -n "${NS}" |grep -c "instana-zookeeper-")
    if [ "${replicaCount}" -le "${podcount}" ];then echo "all Zookeeper replica pods scheduled"; break; fi

    if [ "${timeout_podcount}" -le 0  ];then echo "timeout, abort"; exit 1; fi
    ((timeout_podcount=timeout_podcount-10))
    echo "waiting for pods to be scheduled"
    sleep 10
  done
}

restartPods() {
  local podString="$1"
  kubectl get pod -n "${NS}" |grep "${podString}" |awk '{print $1}' |
    while IFS="" read -r pod; do 
      kubectl -n "${NS}" delete pod/"${pod}"
    done
}

wait4PodsReady() {
  local podString="$1"

  kubectl get pod -n "${NS}" |grep "${podString}" |awk '{print $1}' |
    while IFS="" read -r pod; do
      kubectl -n "${NS}" wait pod/"${pod}" --for=condition=Ready --timeout=300s
    done
}

main() {
  if [ "$#" -ne 1 ]; then
    echo "need to provide 1 parm for backup TIMESTAMP."
    exit 1
  fi
  # velero_cmd='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'

  readonly TIMESTAMP=$1

  # BACKUP_LOCATION=http://minio-instana-1st.fyre.ibm.com:9000/itomsaas16c/velero
  readonly BACKUP_LOCATION=http://9.30.55.245:9000/selfhosted04/velero/db 
  readonly S3_KEYID=zH2ipKjrXPmVJQmNr3Xl
  readonly S3_SECRET=Q1nY24t8X3XWrLETCON0yMuw9R9HNU7saKxluAlX
  readonly BACKUP_USER="clickhouse-user"
  readonly BACKUP_PASSWORD="S1TTWxNr"

  # ${velero_cmd} restore create \
  #   --from-backup instana-clickhouse-${TIMESTAMP} \
  #   --include-namespaces ${NS},instana-zookeeper \
  #   --include-cluster-resources=true \
  #   --wait
  script_folder=$(dirname "$0")

  wait4ClickhousePodsStart
  result=$?
  if [[ ${result} -ne 0 ]]; then echo "Clickhouse replicas starting timeout, abort."; exit 1; fi
  wait4ZookeeperPodsStart
  result=$?
  if [[ ${result} -ne 0 ]]; then echo "Zookeeper replicas starting timeout, abort."; exit 1; fi
  wait4PodsReady "chi-instana-local-"
  restartPods "instana-zookeeper-"
  wait4ZookeeperPodsStart
  wait4PodsReady "instana-zookeeper-"

  shardsCount=$(kubectl -n "${NS}" get clickhouseinstallations.clickhouse.altinity.com instana -ojsonpath="{.spec.configuration.clusters[0].layout.shardsCount}")
  replicaCount=$(kubectl -n ${NS} get clickhouseinstallations.clickhouse.altinity.com instana -ojsonpath="{.spec.configuration.clusters[0].layout.replicasCount}")
  result=$?
  if [[ ${result} -ne 0 ]]; then echo "Clickhouse get shard configuration timeout, abort."; exit 1; fi

  echo "${shardsCount} shards to restore"
  ((shardsNumber=shardsCount-1))
  ((replicasNumber=replicaCount-1))
  for shard in $(seq 0 $shardsNumber); do
    for replica in $(seq 0 $replicasNumber); do
      pod=$(kubectl -n "${NS}" get pod|grep "chi-instana-local-${shard}-${replica}-0"|awk '{print$1}')
      echo "copy ch_db_bk_rst.sh to pod: ${pod}"
      kubectl exec -i -n "${NS}" "${pod}" -c instana-clickhouse -- sh -c "cat > /var/lib/clickhouse/ch_db_bk_rst.sh" < "${script_folder}/ch_db_bk_rst.sh"
      kubectl exec "${pod}" -c instana-clickhouse -n "${NS}"  -- sh -c "chmod 755 /var/lib/clickhouse/ch_db_bk_rst.sh"
      echo "restoring databases"
      oc exec "${pod}" -c instana-clickhouse -n "${NS}"  -- /var/lib/clickhouse/ch_db_bk_rst.sh restore "${BACKUP_LOCATION}" "${S3_KEYID}" "${S3_SECRET}" "${pod}" "${TIMESTAMP}" "${CH_RESTORE_TIMEOUT}" "${BACKUP_USER}" "${BACKUP_PASSWORD}"
      result=$?
      if  [ "$result" == "0" ]; then
          echo "Restore database for shard ${shard} replica ${replica} pod ${pod} success"
          echo "clickhouse restore successful."
      else
          echo "Restore database for shard ${shard} replica ${replica} pod ${pod} failed"
          echo "Failed to restore Clickhouse."
          exit 1
      fi
    done
  done
}

main "$@"
