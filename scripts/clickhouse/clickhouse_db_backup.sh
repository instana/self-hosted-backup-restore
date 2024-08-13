#!/usr/bin/env bash

# Readme:
#   Update the Backup location with your S3 storage configuration:
#   Update BACKUP_USER and BACKUP_PASSWORD with clickhouse credential retrived from Instana env.
#   Use following command to retrive the clickhouse clickhouse credential from Instana env:
#       oc get secret instana-core -n instana-core -ojsonpath={.data."config\.yaml"}|base64 -d|grep clickhouseConfigs -A4|grep -E 'user:|password:'
# 
readonly BACKUP_LOCATION=http://9.30.55.245:9000/selfhosted04/velero/db
readonly S3_KEYID=zH2ipKjrXPmVJQmNr3Xl
readonly S3_SECRET=Q1nY24t8X3XWrLETCON0yMuw9R9HNU7saKxluAlX
readonly BACKUP_USER="clickhouse-user"
readonly BACKUP_PASSWORD="S1TTWxNr"

readonly CH_BACKUP_TIMEOUT=1800 # Increase this number if clickhouse have large amount of data.
readonly NS=instana-clickhouse
# velero_cmd='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'

script_folder=$(dirname "$0")
TIMESTAMP=$(date +%Y%m%d%H%M%S)
kubectl -n ${NS} get pod|grep 'zookeeper\-'|awk '{print $1}' \
  |xargs -I {} kubectl -n ${NS} \
  annotate pod/{} backup.velero.io/backup-volumes-excludes=data \
  --overwrite

# replicasCount=$(kubectl -n ${NS} get clickhouseinstallations.clickhouse.altinity.com instana -ojsonpath={.spec.configuration.clusters[0].layout.replicasCount})
shardsCount=$(kubectl -n ${NS} get clickhouseinstallations.clickhouse.altinity.com instana -ojsonpath="{.spec.configuration.clusters[0].layout.shardsCount}")
replicaCount=$(kubectl -n ${NS} get clickhouseinstallations.clickhouse.altinity.com instana -ojsonpath="{.spec.configuration.clusters[0].layout.replicasCount}")
result=$?
if [[ ${result} -ne 0 ]]; then echo "Clickhouse get configuration timeout, abort."; exit 1; fi

echo "${shardsCount} shards to backup"
((shardsNumber=shardsCount-1))
((replicasNumber=replicaCount-1))
for shard in $(seq 0 $shardsNumber); do
  for replica in $(seq 0 $replicasNumber); do
    pod=$(kubectl -n ${NS} get pod|grep "chi-instana-local-${shard}-${replica}-0"|awk '{print$1}')
    echo "copy ch_db_bk_rst.sh to pod: ${pod}"
    kubectl exec -i -n ${NS} "${pod}" -c instana-clickhouse -- sh -c "cat > /var/lib/clickhouse/ch_db_bk_rst.sh" < "${script_folder}/ch_db_bk_rst.sh"
    kubectl exec "$pod" -c instana-clickhouse -n ${NS}  -- sh -c "chmod 755 /var/lib/clickhouse/ch_db_bk_rst.sh"
    echo "backing up databases"
    oc exec "$pod" -c instana-clickhouse -n ${NS}  -- /var/lib/clickhouse/ch_db_bk_rst.sh backup "${BACKUP_LOCATION}" "${S3_KEYID}" "${S3_SECRET}" "${pod}" "${TIMESTAMP}" "${CH_BACKUP_TIMEOUT}" "${BACKUP_USER}" "${BACKUP_PASSWORD}"
    result=$?
    if  [ "$result" == "0" ]; then
        kubectl exec -i -n ${NS} "${pod}" -c instana-clickhouse -- sh -c "echo ${BACKUP_LOCATION}/${pod}-${TIMESTAMP} > /var/lib/clickhouse/${pod}-${TIMESTAMP}"
        echo "Backup database for shard ${shard} replica ${replica} pod ${pod} success"
        echo "backup location: ${BACKUP_LOCATION}/${pod}-${TIMESTAMP}"
    else
        echo "Backup database for shard ${shard} replica ${replica} pod ${pod} failed"
        echo "Failed to backup Clickhouse."
        exit 1
    fi
  done
done    

echo "Clickhouse backup timestamp: ${TIMESTAMP}"

# Backup
# echo "Start velero backup"
# ${velero_cmd} backup create instana-clickhouse-${TIMESTAMP} \
#   --include-namespaces ${NS},instana-zookeeper \
#   --include-cluster-resources=true \
#   --default-volumes-to-fs-backup \
#   --wait
