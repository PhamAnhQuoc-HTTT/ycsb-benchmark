#!/bin/bash
# ============================================================
# common.sh — Shared config & helpers for YCSB benchmark scripts
# ============================================================
# Source this file from run_*.sh scripts.
#
# Override defaults via environment variables, e.g.:
#   RECORDCOUNT=10000 OPERATIONCOUNT=10000 bash run_mongodb.sh
#
# Default = full benchmark (1M). For smoke testing use small values.
# ============================================================

# Disable MSYS2/Git Bash path conversion (Windows).
# Without this, container-internal paths like /workloads get mangled
# into Windows paths (e.g. C:/Program Files/Git/workloads).
export MSYS_NO_PATHCONV=1

# --- Tunable parameters (override via env) ---
RECORDCOUNT="${RECORDCOUNT:-1000000}"
OPERATIONCOUNT="${OPERATIONCOUNT:-1000000}"
THREADCOUNT="${THREADCOUNT:-16}"
RUNS="${RUNS:-3}"
IMAGE="${IMAGE:-ycsb-runner:0.17.0}"

# --- Workloads to benchmark ---
# Maps friendly name -> workload property file (mounted from host)
WORKLOADS=("a" "b" "c" "f")

# --- Paths ---
# Resolve repo root regardless of where script is called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKLOADS_HOST_DIR="$REPO_ROOT/ycsb/workloads"
RESULTS_BASE="$REPO_ROOT/analysis/results"

# --- Helper: print section header ---
section() {
  echo ""
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
}

# --- Helper: print timestamped log line ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# --- Helper: verify workload files exist on host ---
check_workload_files() {
  for wl in "${WORKLOADS[@]}"; do
    local f="$WORKLOADS_HOST_DIR/workload_${wl}.properties"
    if [[ ! -f "$f" ]]; then
      echo "ERROR: workload file not found: $f"
      echo "Make sure you run this script from the repo (scripts are in ycsb/scripts/)."
      exit 1
    fi
  done
  log "All ${#WORKLOADS[@]} workload files found in $WORKLOADS_HOST_DIR"
}

# --- Helper: print run configuration ---
print_config() {
  log "Benchmark configuration:"
  log "  recordcount    = $RECORDCOUNT"
  log "  operationcount = $OPERATIONCOUNT"
  log "  threadcount    = $THREADCOUNT"
  log "  runs per WL    = $RUNS"
  log "  workloads      = ${WORKLOADS[*]}"
  log "  image          = $IMAGE"
}
