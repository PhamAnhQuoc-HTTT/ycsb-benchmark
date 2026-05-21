# YCSB Benchmark — Distributed Database Performance Evaluation

> **Đánh giá hiệu năng xử lý dữ liệu lớn của các hệ cơ sở dữ liệu phân tán (NoSQL và NewSQL) thông qua thực nghiệm YCSB**

Đồ án liên môn — **Cơ sở dữ liệu phân tán + Dữ liệu lớn**
Đại học Công nghệ Thông tin — VNU-HCM (UIT)
GVHD: ThS. Nguyễn Hồ Duy Trí

## Nhóm thực hiện

| Họ tên | MSSV | Vai trò |
|--------|------|---------|
| Phạm Anh Quốc | 23521307 | Chủ nhiệm — infrastructure (Docker, YCSB runner), benchmark, parse data |
| Trần Thanh Huy | 23520649 | Lý thuyết, workload config, visualize, phân tích |

## Hệ thống đánh giá

| Hệ thống | Version | Kiến trúc | Topology |
|----------|---------|-----------|----------|
| MongoDB | 7.0 | Document NoSQL | Replica Set 3-node (PRIMARY + 2 SECONDARY) |
| Apache Cassandra | 4.1 | Column-family NoSQL | Masterless 3-node, RF=3 |
| CockroachDB | v23.2.4 | NewSQL distributed SQL | 3-node Raft consensus |

## Kịch bản thực nghiệm

1. **4 workload YCSB** (A/B/C/F) × 3 hệ thống × 3 lần chạy = 36 benchmark runs
2. **Scalability test** — Workload A với 1 → 2 → 3 node (tùy chọn)
3. **Fault tolerance test** — Dừng 1 node giữa benchmark, đo recovery time (tùy chọn)

Chỉ số đo: Throughput (ops/sec), Latency p50/p95/p99 (ms), Recovery time (ms).

## Kiến trúc thực nghiệm

```
Windows host (Quốc)
└── Docker Desktop (WSL2, 16GB RAM)
    ├── Network ycsb-mongo-rs-net      → 3 MongoDB containers
    ├── Network ycsb-cass-cluster-net  → 3 Cassandra containers
    ├── Network ycsb-crdb-cluster-net  → 3 CockroachDB containers
    └── ycsb-runner image              → join network của DB cần benchmark
```

YCSB chạy **trong container** (image `ycsb-runner:0.17.0`), join chung Docker network với DB. Nhờ đó YCSB resolve hostname `mongo1/cass1/crdb1...` qua Docker DNS internal, không bị vướng port-mapping NAT của Docker Desktop trên Windows.

## Yêu cầu môi trường

| Tool | Version | Ghi chú |
|------|---------|---------|
| Docker Desktop | 24.0+ với WSL2 backend | Cấp ≥ 16GB RAM cho WSL2 (file `.wslconfig`) |
| Java | 11 (Temurin/Adoptium) | Cho YCSB local; runner image tự bundle Java 11 |
| Python | 3.11 | Cho parse log + visualize |
| Git Bash | (kèm Git for Windows) | Để chạy script `.sh` trên Windows |

Cấu hình `~/.wslconfig`:

```ini
[wsl2]
memory=16GB
processors=8
swap=4GB
```

## Quick Start

### 1. Clone repo

```bash
git clone https://github.com/PhamAnhQuoc-HTTT/ycsb-benchmark.git
cd ycsb-benchmark
```

### 2. Build YCSB runner image (làm 1 lần, ~25-30 phút)

```bash
docker build -t ycsb-runner:0.17.0 ./docker/ycsb-runner
```

### 3. Khởi động cluster + tạo schema

**MongoDB:**
```bash
cd docker/mongodb && docker compose up -d
# Đợi healthy, rồi init replica set:
docker exec ycsb-mongo1 mongosh --quiet --eval "rs.initiate({_id:'ycsb-rs',members:[{_id:0,host:'mongo1:27017',priority:2},{_id:1,host:'mongo2:27017',priority:1},{_id:2,host:'mongo3:27017',priority:1}]})"
```
MongoDB không cần tạo schema — YCSB tự tạo collection.

**Cassandra:**
```bash
cd ../cassandra && docker compose up -d
# Đợi 5-8 phút cho 3 node UN, rồi tạo schema:
docker exec ycsb-cass1 cqlsh -e "CREATE KEYSPACE IF NOT EXISTS ycsb WITH replication={'class':'SimpleStrategy','replication_factor':3}; CREATE TABLE IF NOT EXISTS ycsb.usertable (y_id varchar PRIMARY KEY, field0 varchar, field1 varchar, field2 varchar, field3 varchar, field4 varchar, field5 varchar, field6 varchar, field7 varchar, field8 varchar, field9 varchar);"
```

**CockroachDB:**
```bash
cd ../cockroachdb && docker compose up -d
# Init cluster:
docker exec ycsb-crdb1 cockroach init --insecure --host=crdb1:26257
# Tạo schema:
docker exec ycsb-crdb1 cockroach sql --insecure --host=crdb1:26257 -e "CREATE DATABASE IF NOT EXISTS ycsb; USE ycsb; CREATE TABLE IF NOT EXISTS usertable (ycsb_key VARCHAR(255) PRIMARY KEY, field0 TEXT, field1 TEXT, field2 TEXT, field3 TEXT, field4 TEXT, field5 TEXT, field6 TEXT, field7 TEXT, field8 TEXT, field9 TEXT);"
```

### 4. Chạy benchmark

Dùng **Git Bash** (không phải PowerShell — script là `.sh`).

Smoke test trước (10K records, verify pipeline):
```bash
cd ycsb/scripts
RECORDCOUNT=10000 OPERATIONCOUNT=10000 RUNS=1 THREADCOUNT=4 bash run_mongodb.sh
```

Full benchmark (1M records, 3 runs, mặc định):
```bash
bash run_mongodb.sh       # ~2-4 tiếng
bash run_cassandra.sh     # ~2-4 tiếng
bash run_cockroachdb.sh   # ~3-5 tiếng
```

**Lưu ý**: Chạy 1 DB tại 1 thời điểm, stop 2 DB còn lại để giải phóng RAM. Xem `ycsb/scripts/README.md` để biết chi tiết workflow.

### 5. Parse logs → CSV

Sau khi benchmark xong, parse logs thành CSV:

```bash
cd analysis
python parse_logs.py
```

Output:
- `analysis/results/summary/summary_raw.csv` — 1 dòng mỗi run (36 dòng khi đủ 3 DB)
- `analysis/results/summary/summary_mean.csv` — trung bình theo (db, workload), kèm std/min/max

CSV này là input cho bước visualize.

### 6. Visualize (Huy)

Từ `summary_mean.csv`, vẽ:
- Throughput grouped bar chart (4 workload × 3 DB)
- Latency p95/p99 comparison
- (tùy chọn) scalability, fault tolerance

## Cấu trúc repo

```
ycsb-benchmark/
├── docker/
│   ├── mongodb/         # MongoDB 7.0 replica set
│   ├── cassandra/       # Cassandra 4.1 cluster
│   ├── cockroachdb/     # CockroachDB v23.2.4 cluster
│   └── ycsb-runner/     # YCSB 0.17 + PostgreSQL JDBC driver
├── ycsb/
│   ├── workloads/       # workload_a/b/c/f.properties
│   └── scripts/         # common.sh, run_*.sh, README.md
├── analysis/
│   ├── parse_logs.py    # parse YCSB logs -> CSV
│   ├── results/
│   │   ├── mongodb/     # logs
│   │   ├── cassandra/
│   │   ├── cockroachdb/
│   │   └── summary/     # summary_raw.csv, summary_mean.csv
│   └── notebooks/       # Jupyter EDA (Huy)
├── docs/                # DEVELOPMENT_LOG.md, HANDOFF.md
├── report/              # Báo cáo + references
└── README.md
```

## Kết quả MongoDB (1M records, 3 runs, threadcount=16)

| Workload | TB Throughput (ops/sec) | Ghi chú |
|----------|------------------------|---------|
| A (50/50 read/update) | ~942 | write qua writeConcern=majority chậm |
| B (95/5 read/update) | ~3823 | read-heavy |
| C (100% read) | ~6405 | nhanh nhất |
| F (50/50 RMW) | ~893 | read-modify-write chậm nhất |

Cassandra và CockroachDB sẽ benchmark tiếp.

## Tài liệu

- `docs/DEVELOPMENT_LOG.md` — Nhật ký kỹ thuật: lỗi đã gặp + cách fix, design decisions
- `docs/HANDOFF.md` — Context cho người mới / AI assistant
- `ycsb/scripts/README.md` — Hướng dẫn chi tiết chạy benchmark
- Bài báo cơ sở: E. Dritsas and M. Trigka, "Database Systems in the Big Data Era," *IEEE Access*, vol. 13, pp. 95068-95084, 2025. [DOI](https://doi.org/10.1109/ACCESS.2025.3572059)

## Tiến độ

- [x] Phase 0 — Environment setup
- [x] Phase 1 — Repo structure
- [x] Phase 2 — 3 cluster + YCSB pipeline verified
- [x] Phase 3 — Workload files + run scripts + parse_logs.py
- [x] Phase 4a — Benchmark MongoDB (1M, 3 runs) ✓
- [ ] Phase 4b — Benchmark Cassandra
- [ ] Phase 4c — Benchmark CockroachDB
- [ ] Phase 5 — Visualize + phân tích (Huy)
- [ ] Phase 6 — Viết báo cáo