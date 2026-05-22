#!/bin/bash
# ============================================================
# run_fault_tolerance.sh — YCSB fault tolerance test
# ============================================================
# Scenario:
#   1. Run YCSB (workload A) with -s flag (per-10s throughput to stderr)
#   2. After KILL_DELAY seconds, stop one node mid-benchmark
#   3. Let it run DOWN_DURATION seconds with node down
#   4. Restart the node (measure recovery)
#   5. Save full log with timestamps for analysis
#
# Usage:
#   bash run_fault_tolerance.sh <db>
#   bash run_fault_tolerance.sh mongodb
#   bash run_fault_tolerance.sh cassandra
#   bash run_fault_tolerance.sh cockroachdb
#
# Prerequisites:
#   - Target cluster running + data already loaded (1M records)
#   - ycsb-runner:0.17.0 image built
#
# Tunables (env):
#   KILL_DELAY=30        seconds before killing a node
#   DOWN_DURATION=60     seconds to keep node down before restart
#   OPERATIONCOUNT=500000  ops for the run (lower = shorter test)
#   THREADCOUNT=16
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DB="${1:-}"
if [[ -z "$DB" ]]; then
  echo "Usage: bash run_fault_tolerance.sh <mongodb|cassandra|cockroachdb>"
  exit 1
fi

# Tunables specific to fault tolerance
KILL_DELAY="${KILL_DELAY:-30}"
DOWN_DURATION="${DOWN_DURATION:-60}"
FT_OPERATIONCOUNT="${OPERATIONCOUNT:-500000}"

# ------------------------------------------------------------
# DB-specific config: network, binding, run params, node to kill
# ------------------------------------------------------------
case "$DB" in
  mongodb)
    NETWORK="ycsb-mongo-rs-net"
    DB_BINDING="mongodb"
    KILL_NODE="ycsb-mongo3"   # a SECONDARY (priority 1)
    RUN_ARGS=(
      -p mongodb.url="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/ycsb?replicaSet=ycsb-rs"
      -p mongodb.writeConcern=majority
    )
    ;;
  cassandra)
    NETWORK="ycsb-cass-cluster-net"
    DB_BINDING="cassandra-cql"
    KILL_NODE="ycsb-cass3"
    RUN_ARGS=(
      -p hosts="cass1,cass2,cass3"
      -p cassandra.keyspace=ycsb
    )
    ;;
  cockroachdb)
    NETWORK="ycsb-crdb-cluster-net"
    DB_BINDING="jdbc"
    KILL_NODE="ycsb-crdb3"
    RUN_ARGS=(
      -p db.driver=org.postgresql.Driver
      -p db.url="jdbc:postgresql://crdb1:26257/ycsb?sslmode=disable"
      -p db.user=root
      -p db.passwd=""
      -p db.batchsize=100
      -p jdbc.autocommit=true
    )
    ;;
  *)
    echo "ERROR: unknown db '$DB'. Use mongodb | cassandra | cockroachdb."
    exit 1
    ;;
esac

RESULTS_DIR="$RESULTS_BASE/$DB"
mkdir -p "$RESULTS_DIR"
FT_LOG="$RESULTS_DIR/log_${DB}_a_fault.txt"
EVENTS_LOG="$RESULTS_DIR/log_${DB}_fault_events.txt"

section "Fault Tolerance Test — $DB"
log "Config: KILL_DELAY=${KILL_DELAY}s, DOWN_DURATION=${DOWN_DURATION}s, operationcount=${FT_OPERATIONCOUNT}"
log "Node to kill: $KILL_NODE"
check_workload_files

# Verify the kill-target container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${KILL_NODE}$"; then
  echo "ERROR: container $KILL_NODE is not running. Start the cluster first."
  exit 1
fi

# Record events with timestamps for later correlation with throughput
: > "$EVENTS_LOG"
record_event() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$EVENTS_LOG"
}

# ------------------------------------------------------------
# Start YCSB run in background, with -s (status every 10s -> stderr)
# stdout+stderr both captured to FT_LOG
# ------------------------------------------------------------
record_event "START benchmark (workload A, -s status mode)"
log "Launching YCSB in background... (output -> $FT_LOG)"

docker run --rm --network="$NETWORK" \
  -v "$WORKLOADS_HOST_DIR:/workloads:ro" \
  "$IMAGE" \
  run "$DB_BINDING" \
  -P /workloads/workload_a.properties \
  "${RUN_ARGS[@]}" \
  -p recordcount="$RECORDCOUNT" \
  -p operationcount="$FT_OPERATIONCOUNT" \
  -p threadcount="$THREADCOUNT" \
  -s \
  > "$FT_LOG" 2>&1 &

YCSB_PID=$!
log "YCSB background PID: $YCSB_PID"

# ------------------------------------------------------------
# Wait, then kill a node
# ------------------------------------------------------------
log "Waiting ${KILL_DELAY}s before killing node..."
sleep "$KILL_DELAY"

# Check YCSB still running (didn't finish too fast)
if ! kill -0 "$YCSB_PID" 2>/dev/null; then
  log "WARNING: YCSB finished before kill point. Increase OPERATIONCOUNT."
  wait "$YCSB_PID"
  record_event "benchmark finished before fault injection"
  exit 0
fi

record_event "STOP node $KILL_NODE (fault injection)"
docker stop "$KILL_NODE" >/dev/null
log "Node $KILL_NODE stopped. Running ${DOWN_DURATION}s with node down..."

# ------------------------------------------------------------
# Wait with node down, then restart
# ------------------------------------------------------------
sleep "$DOWN_DURATION"

record_event "START node $KILL_NODE (recovery)"
docker start "$KILL_NODE" >/dev/null
log "Node $KILL_NODE restarted. Waiting for benchmark to finish..."

# ------------------------------------------------------------
# Wait for benchmark to complete
# ------------------------------------------------------------
wait "$YCSB_PID"
record_event "END benchmark"

section "Fault Tolerance Test COMPLETE — $DB"

# Summary
if grep -q "\[OVERALL\], Throughput" "$FT_LOG"; then
  log "Overall result:"
  grep "\[OVERALL\], Throughput" "$FT_LOG" | sed 's/^/    /'
  grep "\[OVERALL\], RunTime" "$FT_LOG" | sed 's/^/    /'
else
  log "WARNING: benchmark may have failed. Check $FT_LOG"
  tail -8 "$FT_LOG" | sed 's/^/    /'
fi

log "Throughput timeline (per-10s samples from -s flag):"
grep -E "current ops/sec" "$FT_LOG" | head -40 | sed 's/^/    /'

log ""
log "Files:"
log "  benchmark log: $FT_LOG"
log "  events log:    $EVENTS_LOG"
log ""
log "Correlate timestamps in events log with the throughput timeline"
log "to see the drop at fault injection and recovery after restart."

# Verify node is healthy again
log ""
log "Post-test cluster state:"
case "$DB" in
  mongodb)
    docker exec ycsb-mongo1 mongosh --quiet --eval \
      "rs.status().members.forEach(m => print('    ' + m.name + ' = ' + m.stateStr))" 2>/dev/null || true
    ;;
  cassandra)
    sleep 30  # cassandra needs time to rejoin
    docker exec ycsb-cass1 nodetool status 2>/dev/null | grep -E "^(UN|DN)" | sed 's/^/    /' || true
    ;;
  cockroachdb)
    docker exec ycsb-crdb1 cockroach node status --insecure --host=crdb1:26257 2>/dev/null | sed 's/^/    /' || true
    ;;
esac
