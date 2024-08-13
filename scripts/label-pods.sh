#!/bin/bash

ns=instana-postgres
pod=( $(kubectl get pod -n ${ns} |grep "cnpg-cloudnative-pg-"|awk '{print $1}') )
kubectl -n ${ns} label pod/${pod} velero.io/exclude-from-backup=true --overwrite

ns=instana-clickhouse
click_pod=`kubectl get pod -n ${ns}|grep 'clickhouse\-operator'|awk '{print $1}'`
kubectl -n ${ns} label pod/${click_pod} velero.io/exclude-from-backup=true --overwrite

podlist=( $(kubectl -n ${ns} get pod|grep 'instana\-zookeeper\-'|awk '{print $1}') )
for pod in "${podlist[@]}"
do
  kubectl -n ${ns} annotate pod/${pod} backup.velero.io/backup-volumes-excludes=data --overwrite
done
