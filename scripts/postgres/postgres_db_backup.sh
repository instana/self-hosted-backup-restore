#!/usr/bin/env bash

# Readme:
#   Update BACKUP_USER and BACKUP_PASSWORD with postgres credential retrived from Instana env.
#   Use following command to retrive the postgres credential from Instana env:
#     oc get secret instana-core -n instana-core -ojsonpath={.data."config\.yaml"}|base64 -d|grep 'postgresConfigs:' -A4|grep -E 'user:|password:'
# 

if [ "$#" -ne 1 ]; then
  echo "need to provide 1 parm for Postgres password."
  exit 1
fi

POSTGRES_PASSWORD=$1
NS=instana-postgres
script_folder=$(dirname "$0")
# velero_cmd='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'

pod=( "$(kubectl get pod -n ${NS} |grep 'cnpg-cloudnative-pg-'|awk '{print $1}')" )
kubectl -n ${NS} label pod/"${pod[0]}" velero.io/exclude-from-backup=true --overwrite

kubectl get pod -n ${NS} |grep "postgres-"|awk '{print $1}' |
while read -r pg_pod; do
  echo copy pg_db_bk_rst.sh to pod: "${pg_pod}"
  oc cp "${script_folder}"/pg_db_bk_rst.sh "${pg_pod}":/var/lib/postgresql/data -c postgres -n "${NS}"
  echo "backing up databases"
  oc exec -t "${pg_pod}" -c postgres -n "${NS}"  -- /var/lib/postgresql/data/pg_db_bk_rst.sh backup "${POSTGRES_PASSWORD}"
done

# ${velero_cmd} backup create $2 \
#   --include-namespaces instana-postgres \
#   --include-cluster-resources=true \
#   --default-volumes-to-fs-backup \
#   --wait

