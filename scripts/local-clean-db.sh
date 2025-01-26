# Login in as the root postgres user
psql -U postgres
# >postgrespw 

# Recreate the sui_indexer database
drop database sui_indexer;
create database sui_indexer;
\q
