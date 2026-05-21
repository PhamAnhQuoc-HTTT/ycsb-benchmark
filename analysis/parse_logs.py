#!/usr/bin/env python3
"""
parse_logs.py — Parse YCSB benchmark logs into a tidy CSV summary.

Reads all log files under analysis/results/<db>/log_<db>_<workload>_run<N>.txt
and extracts per-operation metrics (throughput, latency percentiles), then
writes:
  - analysis/results/summary/summary_raw.csv   (one row per run)
  - analysis/results/summary/summary_mean.csv  (averaged over runs)

Usage:
  python parse_logs.py
  python parse_logs.py --results-dir ../analysis/results

Works for MongoDB, Cassandra, CockroachDB logs (same YCSB output format).
"""

import argparse
import csv
import re
import statistics
from pathlib import Path

# ------------------------------------------------------------
# Regex patterns for YCSB output lines
# Format: [SECTION], Metric, value
# Example: [READ], 95thPercentileLatency(us), 4675
# ------------------------------------------------------------
RE_THROUGHPUT = re.compile(r"^\[OVERALL\],\s*Throughput\(ops/sec\),\s*([\d.]+)")
RE_RUNTIME = re.compile(r"^\[OVERALL\],\s*RunTime\(ms\),\s*([\d.]+)")

# Operation sections we care about (skip CLEANUP, GC, etc.)
OP_SECTIONS = ["READ", "UPDATE", "INSERT", "READ-MODIFY-WRITE", "SCAN"]

# Metrics within an operation section
# group(1) = section, group(2) = metric name, group(3) = value
RE_OP_METRIC = re.compile(
    r"^\[(READ|UPDATE|INSERT|READ-MODIFY-WRITE|SCAN)\],\s*"
    r"(Operations|AverageLatency\(us\)|MinLatency\(us\)|MaxLatency\(us\)|"
    r"95thPercentileLatency\(us\)|99thPercentileLatency\(us\)|Return=OK),\s*"
    r"([\d.]+)"
)

# Filename pattern: log_<db>_<workload>_run<N>.txt
RE_FILENAME = re.compile(r"^log_([a-z]+)_([a-z])_run(\d+)\.txt$")


def parse_log_file(path: Path) -> dict | None:
    """Parse a single YCSB log file. Returns a flat dict of metrics, or None if invalid."""
    m = RE_FILENAME.match(path.name)
    if not m:
        return None  # not a run log (could be load log)

    db, workload, run = m.group(1), m.group(2), int(m.group(3))

    record = {
        "db": db,
        "workload": workload,
        "run": run,
        "throughput_ops_sec": None,
        "runtime_ms": None,
    }

    text = path.read_text(encoding="utf-8", errors="replace")

    for line in text.splitlines():
        line = line.strip()

        # OVERALL throughput / runtime
        mt = RE_THROUGHPUT.match(line)
        if mt:
            record["throughput_ops_sec"] = float(mt.group(1))
            continue
        mr = RE_RUNTIME.match(line)
        if mr:
            record["runtime_ms"] = float(mr.group(1))
            continue

        # Per-operation metrics
        mo = RE_OP_METRIC.match(line)
        if mo:
            section = mo.group(1).lower().replace("-", "_")  # read_modify_write
            metric = mo.group(2)
            value = float(mo.group(3))

            # Normalize metric name into a short column suffix
            if metric == "Operations":
                col = f"{section}_ops"
            elif metric == "AverageLatency(us)":
                col = f"{section}_avg_us"
            elif metric == "MinLatency(us)":
                col = f"{section}_min_us"
            elif metric == "MaxLatency(us)":
                col = f"{section}_max_us"
            elif metric == "95thPercentileLatency(us)":
                col = f"{section}_p95_us"
            elif metric == "99thPercentileLatency(us)":
                col = f"{section}_p99_us"
            elif metric == "Return=OK":
                col = f"{section}_ok"
            else:
                continue
            record[col] = value

    # Validity check: must have throughput
    if record["throughput_ops_sec"] is None:
        print(f"  WARNING: no throughput found in {path.name} (run may have failed)")
        return None

    return record


def collect_records(results_dir: Path) -> list[dict]:
    """Walk all <db> subfolders, parse every run log."""
    records = []
    for db_dir in sorted(results_dir.iterdir()):
        if not db_dir.is_dir() or db_dir.name == "summary":
            continue
        for log_file in sorted(db_dir.glob("log_*_run*.txt")):
            rec = parse_log_file(log_file)
            if rec:
                records.append(rec)
                tp = rec["throughput_ops_sec"]
                print(f"  parsed {log_file.name}: throughput={tp:.2f} ops/sec")
    return records


def write_raw_csv(records: list[dict], out_path: Path):
    """Write one row per run (all metrics)."""
    if not records:
        print("No records to write.")
        return

    # Union of all keys across records (some workloads lack update/rmw columns)
    all_keys = []
    for r in records:
        for k in r.keys():
            if k not in all_keys:
                all_keys.append(k)

    # Sort: identity columns first, then the rest
    id_cols = ["db", "workload", "run", "throughput_ops_sec", "runtime_ms"]
    metric_cols = sorted(k for k in all_keys if k not in id_cols)
    fieldnames = id_cols + metric_cols

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in sorted(records, key=lambda x: (x["db"], x["workload"], x["run"])):
            writer.writerow(r)
    print(f"\nWrote raw CSV: {out_path} ({len(records)} rows)")


def write_mean_csv(records: list[dict], out_path: Path):
    """Average metrics over runs, grouped by (db, workload)."""
    if not records:
        return

    # Group by (db, workload)
    groups: dict[tuple, list[dict]] = {}
    for r in records:
        key = (r["db"], r["workload"])
        groups.setdefault(key, []).append(r)

    # Determine numeric columns to average
    id_cols = {"db", "workload", "run"}
    numeric_cols = []
    for r in records:
        for k, v in r.items():
            if k not in id_cols and isinstance(v, (int, float)) and k not in numeric_cols:
                numeric_cols.append(k)
    numeric_cols = sorted(numeric_cols)
    # Keep throughput first for readability
    if "throughput_ops_sec" in numeric_cols:
        numeric_cols.remove("throughput_ops_sec")
        numeric_cols.insert(0, "throughput_ops_sec")

    fieldnames = ["db", "workload", "n_runs"] + numeric_cols + [
        "throughput_std", "throughput_min", "throughput_max"
    ]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for (db, wl), recs in sorted(groups.items()):
            row = {"db": db, "workload": wl, "n_runs": len(recs)}

            for col in numeric_cols:
                vals = [r[col] for r in recs if r.get(col) is not None]
                row[col] = round(statistics.mean(vals), 2) if vals else ""

            # Throughput spread
            tps = [r["throughput_ops_sec"] for r in recs if r.get("throughput_ops_sec")]
            if len(tps) >= 2:
                row["throughput_std"] = round(statistics.stdev(tps), 2)
            else:
                row["throughput_std"] = 0.0
            row["throughput_min"] = round(min(tps), 2) if tps else ""
            row["throughput_max"] = round(max(tps), 2) if tps else ""

            writer.writerow(row)

    n_groups = len(groups)
    print(f"Wrote mean CSV: {out_path} ({n_groups} db/workload combinations)")


def main():
    ap = argparse.ArgumentParser(description="Parse YCSB logs into CSV summary")
    ap.add_argument(
        "--results-dir",
        default=None,
        help="Path to analysis/results (default: auto-detect relative to script)",
    )
    args = ap.parse_args()

    if args.results_dir:
        results_dir = Path(args.results_dir).resolve()
    else:
        # Script lives in analysis/, results in analysis/results/
        script_dir = Path(__file__).resolve().parent
        results_dir = script_dir / "results"

    if not results_dir.exists():
        print(f"ERROR: results dir not found: {results_dir}")
        return

    print(f"Parsing logs from: {results_dir}\n")
    records = collect_records(results_dir)

    if not records:
        print("\nNo valid run logs found. Nothing to write.")
        return

    summary_dir = results_dir / "summary"
    write_raw_csv(records, summary_dir / "summary_raw.csv")
    write_mean_csv(records, summary_dir / "summary_mean.csv")

    print(f"\nDone. Parsed {len(records)} runs across "
          f"{len(set((r['db'], r['workload']) for r in records))} db/workload combos.")


if __name__ == "__main__":
    main()
