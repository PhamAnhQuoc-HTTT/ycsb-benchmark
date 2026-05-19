# YCSB Benchmark — Distributed Database Performance Evaluation

> **Đánh giá hiệu năng xử lý dữ liệu lớn của các hệ cơ sở dữ liệu phân tán (NoSQL và NewSQL) thông qua thực nghiệm YCSB**

Đồ án liên môn — **Cơ sở dữ liệu phân tán + Dữ liệu lớn**
Đại học Công nghệ Thông tin — VNU-HCM (UIT)
GVHD: ThS. Nguyễn Hồ Duy Trí

## Nhóm thực hiện

| Họ tên | MSSV | Vai trò |
|--------|------|---------|
| Phạm Anh Quốc | 23521307 | Chủ nhiệm — infrastructure (Docker, YCSB runner), benchmark, visualization |
| Trần Thanh Huy | 23520649 | Lý thuyết, YCSB workload config, run scripts, analysis |

## Hệ thống đánh giá

| Hệ thống | Version | Kiến trúc | Topology |
|----------|---------|-----------|----------|
| MongoDB | 7.0 | Document NoSQL | Replica Set 3-node (PRIMARY + 2 SECONDARY) |
| Apache Cassandra | 4.1 | Column-family NoSQL | Masterless 3-node, RF=3 |
| CockroachDB | v23.2.4 | NewSQL distributed SQL | 3-node Raft consensus |

## Kịch bản thực nghiệm

1. **4 workload YCSB** (A/B/C/F) × 3 hệ thống × 3 lần chạy = 36 benchmark runs
2. **Scalability test** — Workload A với 1 → 2 → 3 node
3. **Fault tolerance test** — Dừng 1 node giữa benchmark, đo recovery time

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

YCSB chạy **trong container** (image `ycsb-runner:0.17.0`), join chung Docker network với DB. Nhờ đó YCSB resolve hostname `mongo1/cass1/crdb1...` qua Docker DNS internal, không bị vướng port-mapping NAT của Docker Desktop trên Windows. Đây là điểm thiết kế quan trọng — sẽ trình bày trong Chương 3 báo cáo.

## Yêu cầu môi trường

| Tool | Version | Ghi chú |
|------|---------|---------|
| Docker Desktop | 24.0+ với WSL2 backend | Cấp ≥ 16GB RAM cho WSL2 (file `.wslconfig`) |
| Java | 11 (Temurin/Adoptium) | Cho YCSB local; runner image tự bundle Java 11 |
| Python | 3.11 | Cho phân tích log (pandas, matplotlib) |
| Git | 2.40+ | |
| RAM máy | ≥ 16GB | Chạy 1 cluster 3-node cần ~6GB |

Cấu hình `~/.wslconfig` đề xuất:

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

### 2. Build YCSB runner image (làm 1 lần)

```bash
docker build -t ycsb-runner:0.17.0 ./docker/ycsb-runner
```

Lưu ý: lần đầu build mất ~25-30 phút (tải base image + YCSB 0.17 + PostgreSQL driver). Lần sau nhờ Docker layer cache, gần như instant.

### 3. Chạy MongoDB Replica Set

```bash
cd docker/mongodb
docker compose up -d
# Đợi ~30s cho healthcheck pass
docker compose ps   # Expect 3 containers (healthy)
```

Khởi tạo replica set (chỉ làm lần đầu):

```bash
docker exec ycsb-mongo1 mongosh --quiet --eval "
rs.initiate({
  _id: 'ycsb-rs',
  members: [
    { _id: 0, host: 'mongo1:27017', priority: 2 },
    { _id: 1, host: 'mongo2:27017', priority: 1 },
    { _id: 2, host: 'mongo3:27017', priority: 1 }
  ]
})
"
```

Verify topology (sau ~15s cho election xong):

```bash
docker exec ycsb-mongo1 mongosh --quiet --eval \
  "rs.status().members.forEach(m => print(m.name + ' = ' + m.stateStr))"
```

Mong đợi: `mongo1:27017 = PRIMARY`, `mongo2/3:27017 = SECONDARY`.

Test YCSB load (100 records, smoke test):

```bash
docker run --rm --network=ycsb-mongo-rs-net ycsb-runner:0.17.0 \
  load mongodb -P /opt/ycsb/workloads/workloada \
  -p mongodb.url="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/ycsb?replicaSet=ycsb-rs" \
  -p mongodb.writeConcern=majority \
  -p recordcount=100 -p threadcount=4
```

### 4. Chạy Cassandra cluster

```bash
cd ../cassandra
docker compose up -d
# Đợi ~5-8 phút (3 node bootstrap tuần tự, gossip protocol)
docker compose ps
```

Verify ring:

```bash
docker exec ycsb-cass1 nodetool status   # Expect 3 lines starting with "UN"
```

Tạo keyspace + table (chỉ làm lần đầu):

```bash
docker exec ycsb-cass1 cqlsh -e "
CREATE KEYSPACE IF NOT EXISTS ycsb WITH replication = {'class':'SimpleStrategy', 'replication_factor':3};
USE ycsb;
CREATE TABLE IF NOT EXISTS usertable (
  y_id varchar PRIMARY KEY,
  field0 varchar, field1 varchar, field2 varchar, field3 varchar, field4 varchar,
  field5 varchar, field6 varchar, field7 varchar, field8 varchar, field9 varchar
);
"
```

Test YCSB load:

```bash
docker run --rm --network=ycsb-cass-cluster-net ycsb-runner:0.17.0 \
  load cassandra-cql -P /opt/ycsb/workloads/workloada \
  -p hosts="cass1,cass2,cass3" \
  -p cassandra.keyspace=ycsb \
  -p recordcount=100 -p threadcount=4
```

### 5. Chạy CockroachDB cluster

```bash
cd ../cockroachdb
docker compose up -d
# Đợi ~20s
```

Init cluster (chỉ làm lần đầu, **bắt buộc**):

```bash
docker exec ycsb-crdb1 cockroach init --insecure --host=crdb1:26257
```

Đợi 15s, verify:

```bash
docker exec ycsb-crdb1 cockroach node status --insecure --host=crdb1:26257
```

Mong đợi: 3 node với `is_available=true`, `is_live=true`.

Tạo database + table:

```bash
docker exec ycsb-crdb1 cockroach sql --insecure --host=crdb1:26257 -e "
CREATE DATABASE IF NOT EXISTS ycsb;
USE ycsb;
CREATE TABLE IF NOT EXISTS usertable (
  ycsb_key VARCHAR(255) PRIMARY KEY,
  field0 TEXT, field1 TEXT, field2 TEXT, field3 TEXT, field4 TEXT,
  field5 TEXT, field6 TEXT, field7 TEXT, field8 TEXT, field9 TEXT
);
"
```

Test YCSB load:

```bash
docker run --rm --network=ycsb-crdb-cluster-net ycsb-runner:0.17.0 \
  load jdbc -P /opt/ycsb/workloads/workloada \
  -p db.driver=org.postgresql.Driver \
  -p db.url="jdbc:postgresql://crdb1:26257/ycsb?sslmode=disable" \
  -p db.user=root -p db.passwd="" \
  -p db.batchsize=100 -p jdbc.autocommit=true \
  -p recordcount=100 -p threadcount=4
```

## Stop / Restart cluster

```bash
# Stop (giữ data trong volume — restart sẽ y nguyên)
docker compose stop

# Start lại (data còn nguyên)
docker compose start

# Xóa hoàn toàn (data, network, container — phải re-init từ đầu)
docker compose down -v
```

## Cấu trúc repo

```
ycsb-benchmark/
├── docker/
│   ├── mongodb/         # MongoDB 7.0 replica set
│   ├── cassandra/       # Cassandra 4.1 cluster
│   ├── cockroachdb/     # CockroachDB v23.2.4 cluster
│   └── ycsb-runner/     # YCSB 0.17 + PostgreSQL JDBC driver
├── ycsb/
│   ├── workloads/       # workload_a/b/c/f.properties (Phase 3)
│   └── scripts/         # run_*.sh (Phase 3)
├── analysis/
│   ├── notebooks/       # Jupyter EDA
│   └── results/         # logs + CSV + figures
├── docs/                # DEVELOPMENT_LOG.md, HANDOFF.md, ...
├── report/              # Báo cáo Word + references
└── README.md
```

## Baseline số liệu (smoke test, 100 records, 4 threads)

| DB | Throughput (ops/sec) | Avg latency | p99 latency |
|----|---------------------|-------------|-------------|
| MongoDB | 112 | 14.6ms | 152ms |
| Cassandra | 26 | 14.5ms | 82ms |
| CockroachDB | 200 | 8.8ms | 40ms |

⚠️ **Đây là smoke test sample 100 records, KHÔNG đại diện cho hiệu năng thực tế.** Phase 3 sẽ chạy 1M records để có số liệu benchmark thật.

## Tài liệu

- `docs/DEVELOPMENT_LOG.md` — Nhật ký kỹ thuật chi tiết: lỗi đã gặp + cách fix
- `docs/HANDOFF.md` — Context project cho người mới (hoặc AI assistant)
- Bài báo cơ sở: E. Dritsas and M. Trigka, "Database Systems in the Big Data Era: Architectures, Performance, and Open Challenges," *IEEE Access*, vol. 13, pp. 95068-95084, 2025. [DOI](https://doi.org/10.1109/ACCESS.2025.3572059)

## Tiến độ

- [x] Phase 0 — Environment setup
- [x] Phase 1 — Repo structure
- [x] Phase 2 — 3 cluster + YCSB pipeline verified
- [ ] Phase 3 — Workload files + run scripts (Huy)
- [ ] Phase 4 — Benchmark thật (1M records)
- [ ] Phase 5 — Phân tích Python + biểu đồ
- [ ] Phase 6 — Viết báo cáo
