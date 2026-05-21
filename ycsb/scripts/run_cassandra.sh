#!/bin/bash
# ============================================================
# run_cassandra.sh — YCSB benchmark for Cassandra cluster
# ============================================================
# Workflow: LOAD once -> RUN each workload x N times
#
# Usage:
#   bash run_cassandra.sh                  # full: 1M records, 3 runs
#   RECORDCOUNT=10000 OPERATIONCOUNT=10000 RUNS=1 bash run_cassandra.sh
#
# Prerequisites:
#   - Cassandra cluster running (docker compose up -d in docker/cassandra)
#   - Keyspace 'ycsb' + table 'usertable' created (see README section 4)
#   - ycsb-runner:0.17.0 image built
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# --- Cassandra-specific config ---
NETWORK="ycsb-cass-cluster-net"
HOSTS="cass1,cass2,cass3"
KEYSPACE="ycsb"
RESULTS_DIR="$RESULTS_BASE/cassandra"
DB_BINDING="cassandra-cql"

mkdir -p "$RESULTS_DIR"

section "Cassandra YCSB Benchmark"
print_config
check_workload_files

log "NOTE: Make sure keyspace '$KEYSPACE' and table 'usertable' exist."
log "      If not, create them first (see README section 4)."

# ------------------------------------------------------------
# LOAD PHASE
# ------------------------------------------------------------
section "LOAD PHASE (Cassandra) — inserting $RECORDCOUNT records"
LOAD_LOG="$RESULTS_DIR/log_cassandra_load.txt"
log "Loading... (output -> $LOAD_LOG)"

docker run --rm --network="$NETWORK" \
  -v "$WORKLOADS_HOST_DIR:/workloads:ro" \
  "$IMAGE" \
  load "$DB_BINDING" \
  -P /workloads/workload_a.properties \
  -p hosts="$HOSTS" \
  -p cassandra.keyspace="$KEYSPACE" \
  -p recordcount="$RECORDCOUNT" \
  -p threadcount="$THREADCOUNT" \
  > "$LOAD_LOG" 2>&1

if grep -q "\[INSERT\], Return=OK" "$LOAD_LOG"; then
  log "LOAD complete. INSERT result:"
  grep "\[INSERT\], Operations" "$LOAD_LOG" | sed 's/^/    /'
  grep "\[INSERT\], Return=OK" "$LOAD_LOG" | sed 's/^/    /'
else
  log "WARNING: LOAD may have failed. Check $LOAD_LOG"
  tail -5 "$LOAD_LOG" | sed 's/^/    /'
fi

# ------------------------------------------------------------
# RUN PHASE
# ------------------------------------------------------------
for wl in "${WORKLOADS[@]}"; do
  for run in $(seq 1 "$RUNS"); do
    section "RUN PHASE (Cassandra) — workload $wl, run $run/$RUNS"
    RUN_LOG="$RESULTS_DIR/log_cassandra_${wl}_run${run}.txt"
    log "Running... (output -> $RUN_LOG)"

    docker run --rm --network="$NETWORK" \
      -v "$WORKLOADS_HOST_DIR:/workloads:ro" \
      "$IMAGE" \
      run "$DB_BINDING" \
      -P /workloads/workload_${wl}.properties \
      -p hosts="$HOSTS" \
      -p cassandra.keyspace="$KEYSPACE" \
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

section "Cassandra benchmark COMPLETE"
log "Logs saved in: $RESULTS_DIR"
ls -1 "$RESULTS_DIR"/log_cassandra_*.txt | sed 's/^/    /'