#!/bin/bash
NETWORK="ycsb-cass-cluster-net"
IMAGE="ycsb-runner:0.17.0"
RESULTS_DIR="analysis/results/cassandra"
mkdir -p $RESULTS_DIR

WORKLOADS=("workloada" "workloadb" "workloadc" "workloadf")

for wl in "${WORKLOADS[@]}"; do
  for run in 1 2 3; do
    echo "=== Cassandra | $wl | Run $run ==="
    docker run --rm --network=$NETWORK $IMAGE \
      run cassandra-cql \
      -P /opt/ycsb/workloads/$wl \
      -p hosts="cass1,cass2,cass3" \
      -p cassandra.keyspace=ycsb \
      -p recordcount=1000000 \
      -p operationcount=1000000 \
      -p threadcount=16 \
      > "$RESULTS_DIR/${wl}_run${run}.log" 2>&1
    echo "Done: $RESULTS_DIR/${wl}_run${run}.log"
  done
done
echo "=== Cassandra benchmark complete ==="
