#!/bin/bash
# Run YCSB benchmark for MongoDB - 4 workloads x 3 runs

NETWORK="ycsb-mongo-rs-net"
IMAGE="ycsb-runner:0.17.0"
MONGO_URL="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/ycsb?replicaSet=ycsb-rs"
RESULTS_DIR="analysis/results/mongodb"
mkdir -p $RESULTS_DIR

WORKLOADS=("workloada" "workloadb" "workloadc" "workloadf")

for wl in "${WORKLOADS[@]}"; do
  for run in 1 2 3; do
    echo "=== MongoDB | $wl | Run $run ==="
    docker run --rm --network=$NETWORK $IMAGE \
      run mongodb \
      -P /opt/ycsb/workloads/$wl \
      -p mongodb.url="$MONGO_URL" \
      -p mongodb.writeConcern=majority \
      -p recordcount=1000000 \
      -p operationcount=1000000 \
      -p threadcount=16 \
      > "$RESULTS_DIR/${wl}_run${run}.log" 2>&1
    echo "Done: $RESULTS_DIR/${wl}_run${run}.log"
  done
done
echo "=== MongoDB benchmark complete ==="
