#!/bin/bash
NETWORK="ycsb-crdb-cluster-net"
IMAGE="ycsb-runner:0.17.0"
RESULTS_DIR="analysis/results/cockroachdb"
mkdir -p $RESULTS_DIR

WORKLOADS=("workloada" "workloadb" "workloadc" "workloadf")

for wl in "${WORKLOADS[@]}"; do
  for run in 1 2 3; do
    echo "=== CockroachDB | $wl | Run $run ==="
    docker run --rm --network=$NETWORK $IMAGE \
      run jdbc \
      -P /opt/ycsb/workloads/$wl \
      -p db.driver=org.postgresql.Driver \
      -p db.url="jdbc:postgresql://crdb1:26257/ycsb?sslmode=disable" \
      -p db.user=root -p db.passwd="" \
      -p db.batchsize=100 -p jdbc.autocommit=true \
      -p recordcount=1000000 \
      -p operationcount=1000000 \
      -p threadcount=16 \
      > "$RESULTS_DIR/${wl}_run${run}.log" 2>&1
    echo "Done: $RESULTS_DIR/${wl}_run${run}.log"
  done
done
echo "=== CockroachDB benchmark complete ==="