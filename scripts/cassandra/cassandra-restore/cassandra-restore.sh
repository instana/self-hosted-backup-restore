#!/usr/bin/env bash
#
# © Copyright IBM Corp. 2024
# 
# 
#

set -o errexit
set -o pipefail
set -o nounset

echo "[INFO] $(date) ############## Cassandra restore started ##############"

#shellcheck source=/dev/null
source cassandra-utils.sh

#This will be applicable to only multi node Cassandra cluster
#This will copy the cassandra_function.sh to all Cassandra pods
./cassandra-script-update.sh


#Trigger restore for the Cassandra keyspaces
echo "[INFO] $(date) Triggering the Cassandra native restore now"
./trigger-cassandra-restore.sh

echo "[INFO] $(date) ############## Cassandra restore completed ##############"
