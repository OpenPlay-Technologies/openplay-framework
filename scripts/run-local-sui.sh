# Clean the current database (keep it gives errors sometimes)
sui genesis --epoch-duration-ms 60000 --force
# Start the local sui network (with graphql)
RUST_LOG="off,sui_node=info" sui start --with-faucet --with-graphql