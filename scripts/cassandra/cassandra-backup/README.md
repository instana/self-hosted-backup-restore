© Copyright IBM Corp. 2024

# Backing up  Cassandra database for Instana

Follow the steps to back up Cassandra database for Instana.

### Prerequest of Cassandra backup
1. Edit instana-config.json file to set the correct cassandraNamespace, it is instana-cassandra by default
2. Edit cassandra-keyspace.json file to set the cassandra keyspaces
3. Edit cassandra cassandradatacenter CR to add additional pv for backup files
```
spec:
......
  storageConfig:
    additionalVolumes:
    - mountPath: /var/lib/cassandra/backup_tar
      name: cassandrabackup
      pvcSpec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
    cassandraDataVolumeClaimSpec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 100Gi
......
```
There may be condition that cassandrabackup are not created and only volumeMounte is added to statefulset and volumeClaimTemplates are not added for cassandrabackup, to workaround this problem, we can delete cassandra statefulset to let the cassandra operator create the cassandra statefulset again. 
```
kubectl delete statefulset instana-cassandra-default-sts -n instana-cassandra
```

### Perform back up process for Cassandra

We have automated the stpes for Cassandra backup. There is a main script `cassandra-backup.sh` at path `scripts/cassandra/cassandra-backup` which includes all the required steps for taking backup of Cassandra. 
   
1. `cassandra-keyspace.json` has the information of the keysspaces of Cassandra, which will be cleaned and backup will run for those keyspaces. So `cassandra-backup.sh` scipt takes keyspaces information from this file. Edit `cassandra-keyspace.json` to set the correct keyspace list before run `cassandra-backup.sh`, keyspace "onprem_tenant0_unit0" need to update according to tenant name and unit name in your env

2. We need to run script `cassandra-backup.sh` to take backup of Cassandra databse in Instana.
  ```
  cd scripts/cassandra/cassandra-backup
  ./cassandra-backup.sh
  ```
   
