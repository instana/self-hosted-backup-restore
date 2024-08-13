© Copyright IBM Corp. 2024

# Restoring the Cassandra database for Instana

Follow the steps to restore Cassandra database for Instana

### Perform restore  process for Cassandra

   We have automated the stpes for Cassandra restore. There is a main script `cassandra-restore.sh` at path `scripts/cassandra/cassandra-restore` which includes all the required steps for restore of Cassandra.
 
   1. `cassandra-keyspace.json` has the information of the keysspaces of Cassandra and restore operation will run for those keyspaces. So `cassandra-restore.sh` scipt takes keyspaces information from this file. Edit `cassandra-keyspace.json` to set the correct keyspace list before run `cassandra-restore.sh`, keyspace "onprem_tenant0_unit0" need to update according to tenant name and unit name in your env
   2. We need to run script `cassandra-restore.sh` to perform restore of Cassandra databse in Instana.
      ```
      cd scripts/cassandra/cassandra-restore
      ./cassandra-restore.sh
      ```