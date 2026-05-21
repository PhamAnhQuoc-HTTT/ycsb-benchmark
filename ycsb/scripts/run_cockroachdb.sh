#!/bin/bash
# ============================================================
# run_cockroachdb.sh — YCSB benchmark for CockroachDB cluster
# ============================================================
# Workflow: LOAD once -> RUN each workload x N times
#
# Usage:
#   bash run_cockroachdb.sh                # full: 1M records, 3 runs
#   RECORDCOUNT=10000 OPERATIONCOUNT=10000 RUNS=1 bash run_cockroachdb.sh
#
# Prerequisites:
#   - CockroachDB cluster running + initialized (cockroach init)
#   - Database 'ycsb' + table 'usertable' created (see README section 5)
#   - ycsb-runner:0.17.0 image built (with PostgreSQL JDBC driver)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# --- CockroachDB-specific config ---
NETWORK="ycsb-crdb-cluster-net"
DB_URL="jdbc:postgresql://crdb1:26257/ycsb?sslmode=disable"
DB_DRIVER="org.postgresql.Driver"
DB_USER="root"
BATCHSIZE=100
RESULTS_DIR="$RESULTS_BASE/cockroachdb"
DB_BINDING="jdbc"

mkdir -p "$RESULTS_DIR"

section "CockroachDB YCSB Benchmark"
print_config
check_workload_files

log "NOTE: Make sure database 'ycsb' and table 'usertable' exist."
log "      If not, create them first (see README section 5)."

# ------------------------------------------------------------
# LOAD PHASE
# ------------------------------------------------------------
section "LOAD PHASE (CockroachDB) — inserting $RECORDCOUNT records"
LOAD_LOG="$RESULTS_DIR/log_cockroachdb_load.txt"
log "Loading... (output -> $LOAD_LOG)"

docker run --rm --network="$NETWORK" \
  -v "$WORKLOADS_HOST_DIR:/workloads:ro" \
  "$IMAGE" \
  load "$DB_BINDING" \
  -P /workloads/workload_a.properties \
  -p db.driver="$DB_DRIVER" \
  -p db.url="$DB_URL" \
  -p db.user="$DB_USER" \
  -p db.passwd="" \
  -p db.batchsize="$BATCHSIZE" \
  -p jdbc.autocommit=true \
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
    section "RUN PHASE (CockroachDB) — workload $wl, run $run/$RUNS"
    RUN_LOG="$RESULTS_DIR/log_cockroachdb_${wl}_run${run}.txt"
    log "Running... (output -> $RUN_LOG)"

    docker run --rm --network="$NETWORK" \
      -v "$WORKLOADS_HOST_DIR:/workloads:ro" \
      "$IMAGE" \
      run "$DB_BINDING" \
      -P /workloads/workload_${wl}.properties \
      -p db.driver="$DB_DRIVER" \
      -p db.url="$DB_URL" \
      -p db.user="$DB_USER" \
      -p db.passwd="" \
      -p db.batchsize="$BATCHSIZE" \
      -p jdbc.autocommit=true \
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

section "CockroachDB benchmark COMPLETE"
log "Logs saved in: $RESULTS_DIR"
ls -1 "$RESULTS_DIR"/log_cockroachdb_*.txt | sed 's/^/    /'