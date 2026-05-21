#!/bin/bash
# ============================================================
# run_mongodb.sh — YCSB benchmark for MongoDB Replica Set
# ============================================================
# Workflow: LOAD once -> RUN each workload x N times
#
# Usage:
#   bash run_mongodb.sh                    # full: 1M records, 3 runs
#   RECORDCOUNT=10000 OPERATIONCOUNT=10000 RUNS=1 bash run_mongodb.sh   # smoke test
#
# Prerequisites:
#   - MongoDB cluster running (docker compose up -d in docker/mongodb)
#   - Replica set initialized (rs.initiate)
#   - ycsb-runner:0.17.0 image built
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# --- MongoDB-specific config ---
NETWORK="ycsb-mongo-rs-net"
MONGO_URL="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/ycsb?replicaSet=ycsb-rs"
WRITE_CONCERN="majority"
RESULTS_DIR="$RESULTS_BASE/mongodb"
DB_BINDING="mongodb"

mkdir -p "$RESULTS_DIR"

section "MongoDB YCSB Benchmark"
print_config
check_workload_files

# ------------------------------------------------------------
# LOAD PHASE — insert RECORDCOUNT records once.
# All workloads run against this same loaded dataset.
# We load using workload_a (load phase only cares about recordcount + fieldcount).
# ------------------------------------------------------------
section "LOAD PHASE (MongoDB) — inserting $RECORDCOUNT records"
LOAD_LOG="$RESULTS_DIR/log_mongodb_load.txt"
log "Loading... (output -> $LOAD_LOG)"

docker run --rm --network="$NETWORK" \
  -v "$WORKLOADS_HOST_DIR:/workloads:ro" \
  "$IMAGE" \
  load "$DB_BINDING" \
  -P /workloads/workload_a.properties \
  -p mongodb.url="$MONGO_URL" \
  -p mongodb.writeConcern="$WRITE_CONCERN" \
  -p recordcount="$RECORDCOUNT" \
  -p threadcount="$THREADCOUNT" \
  > "$LOAD_LOG" 2>&1

if grep -q "\[INSERT\], Return=OK" "$LOAD_LOG"; then
  log "LOAD complete. INSERT result:"
  grep "\[INSERT\], Operations" "$LOAD_LOG" | sed 's/^/    /'
  grep "\[INSERT\], Return=OK" "$LOAD_LOG" | sed 's/^/    /'
else
  log "WARNING: LOAD may have failed. Check $LOAD_LOG"
  log "Last 5 lines:"
  tail -5 "$LOAD_LOG" | sed 's/^/    /'
fi

# ------------------------------------------------------------
# RUN PHASE — for each workload, run RUNS times
# ------------------------------------------------------------
for wl in "${WORKLOADS[@]}"; do
  for run in $(seq 1 "$RUNS"); do
    section "RUN PHASE (MongoDB) — workload $wl, run $run/$RUNS"
    RUN_LOG="$RESULTS_DIR/log_mongodb_${wl}_run${run}.txt"
    log "Running... (output -> $RUN_LOG)"

    docker run --rm --network="$NETWORK" \
      -v "$WORKLOADS_HOST_DIR:/workloads:ro" \
      "$IMAGE" \
      run "$DB_BINDING" \
      -P /workloads/workload_${wl}.properties \
      -p mongodb.url="$MONGO_URL" \
      -p mongodb.writeConcern="$WRITE_CONCERN" \
      -p recordcount="$RECORDCOUNT" \
      -p operationcount="$OPERATIONCOUNT" \
      -p threadcount="$THREADCOUNT" \
      > "$RUN_LOG" 2>&1

    if grep -q "\[OVERALL\], Throughput" "$RUN_LOG"; then
      log "Done. $(grep '\[OVERALL\], Throughput' "$RUN_LOG")"
    else
      log "WARNING: run may have failed. Check $RUN_LOG"
      tail -5 "$RUN_LOG" | sed 's/^/    /'
    fi
  done
done

section "MongoDB benchmark COMPLETE"
log "Logs saved in: $RESULTS_DIR"
ls -1 "$RESULTS_DIR"/log_mongodb_*.txt | sed 's/^/    /'