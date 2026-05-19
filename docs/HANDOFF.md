# HANDOFF — Context cho AI Assistant / Người mới tham gia

> **Mục đích file này**: Khi Huy (hoặc bất kỳ ai) mở chat mới với AI assistant để tiếp tục project, paste hoặc share file này → AI hiểu ngay bối cảnh, không phải hỏi lại từ đầu.

---

## TL;DR (1 phút đọc)

Đây là đồ án benchmark phân tán của UIT — so sánh hiệu năng **MongoDB / Cassandra / CockroachDB** qua **YCSB**. Nhóm 2 người: **Quốc** (chủ nhiệm — đã dựng infrastructure) và **Huy** (lý thuyết + YCSB scripts + phân tích).

**Trạng thái hiện tại (cuối ngày Phase 2)**: 3 cluster 3-node trên Docker đã chạy được, YCSB runner Docker image đã build, pipeline end-to-end verified với 100 records cho cả 3 DB. Tiếp theo là Phase 3: viết YCSB workload files và run scripts.

---

## Bối cảnh học thuật

- **Trường**: Đại học Công nghệ Thông tin — VNU-HCM (UIT)
- **Khoa**: Hệ thống thông tin
- **Đồ án**: Liên môn 2 môn cùng lúc:
  - Cơ sở dữ liệu phân tán (replication, sharding, CAP, consistency)
  - Dữ liệu lớn (throughput, latency, scalability)
- **GVHD**: ThS. Nguyễn Hồ Duy Trí (tri.nhd@uit.edu.vn)
- **Deadline thực tế**: 2-3 tuần (kế hoạch chi tiết 18 ngày)

**Bài báo cơ sở**:
> E. Dritsas and M. Trigka, "Database Systems in the Big Data Era: Architectures, Performance, and Open Challenges," *IEEE Access*, vol. 13, pp. 95068-95084, 2025.

Đây là survey thuần lý thuyết, **không có thực nghiệm**. Đồ án này lấp khoảng trống:
- **Empirical Gap**: thiếu số liệu thực đo
- **Methodological Gap**: thiếu framework chuẩn hóa so sánh

---

## Đối tượng benchmark

| Hệ thống | Version | Loại | Cluster |
|----------|---------|------|---------|
| MongoDB | 7.0 | Document NoSQL | Replica Set 3-node |
| Apache Cassandra | 4.1 | Column-family NoSQL | Masterless 3-node, RF=3 |
| CockroachDB | v23.2.4 | NewSQL distributed SQL | 3-node Raft consensus |

**Phân tích CAP**:
- MongoDB: CP (consistency + partition tolerance), nghiêng C khi `writeConcern=majority`
- Cassandra: AP với tunable consistency
- CockroachDB: CP với ACID đầy đủ qua Raft

---

## YCSB Workloads sẽ chạy

| WL | Read % | Update % | Use case |
|----|--------|----------|----------|
| A | 50% | 50% | Session store (mixed) |
| B | 95% | 5% | Photo tagging (read-heavy) |
| C | 100% | 0% | User profile cache (read-only) |
| F | 50% | 50% RMW | User database (read-modify-write) |

Mỗi WL × 3 DB × 3 lần chạy = **36 benchmark runs**. Plus **scalability test** (1→2→3 node) và **fault tolerance test** (dừng 1 node giữa benchmark).

Recordcount kế hoạch: **1,000,000** (1M records) cho benchmark thật. Smoke test đã làm với 100 records.

---

## Kiến trúc thiết kế đã chọn

### Quyết định quan trọng: Dockerize YCSB

YCSB chạy trong Docker container (image `ycsb-runner:0.17.0`), **join chung network với DB**. Lý do:

Trước đó đã thử chạy YCSB từ Windows host kết nối tới `localhost:27017/27018/27019` — fail vì MongoDB driver dùng SDAM (Server Discovery and Monitoring), nó hỏi PRIMARY "members là ai?", nhận về list hostname `mongo1/2/3` (set khi `rs.initiate`) → driver thử resolve hostname từ Windows host → DNS fail vì hostname chỉ tồn tại trong Docker network.

Giải pháp: YCSB chạy trong container, qua Docker DNS internal là resolve được. Cùng pattern áp dụng cho Cassandra và CockroachDB.

**Chi tiết kỹ thuật**: xem `docs/DEVELOPMENT_LOG.md` section 2.4 và Error 2.

### Resource limits

Mỗi container DB giới hạn **2GB RAM, 2 CPU** (compose `deploy.resources.limits`). Tổng 1 cluster 3-node = 6GB. WSL2 cấp 16GB → còn headroom.

Cassandra cần set thêm `MAX_HEAP_SIZE=1G` để JVM không lấy quá 50% container limit (off-heap memory ~400MB + page cache).

CockroachDB set `--cache=512MiB --max-sql-memory=512MiB` cùng lý do.

---

## Cấu hình benchmark thống nhất (đã agreed)

Các tham số phải **giống nhau** giữa 3 DB để fair comparison:

- `recordcount`: 100,000 (dev test) và 1,000,000 (benchmark thật)
- `operationcount`: 1,000,000 cho run phase
- `threadcount`: 16
- Số lần chạy mỗi config: ≥ 3, lấy trung bình

Khác biệt theo DB (do nature của DB):

- MongoDB: `writeConcern=majority` (test strong consistency)
- Cassandra: default consistency `ONE` (Cassandra binding default), có thể test thêm `QUORUM` ở scenario riêng
- CockroachDB: `db.batchsize=100`, `jdbc.autocommit=true`

---

## Phân chia công việc

| Người | Đã làm | Đang làm | Sẽ làm |
|-------|--------|----------|--------|
| Quốc | Phase 0-2 (env, repo, 3 cluster, YCSB runner) | Documentation | Phase 4 benchmark, Phase 5 analysis (Python) |
| Huy | (chưa bắt đầu) | Phase 3 workloads + scripts | Lý thuyết Chương 2, viết báo cáo phần lý thuyết |

---

## Phase 3 — Việc Huy cần làm

### 3.1 Tạo workload files trong `ycsb/workloads/`

4 file: `workload_a.properties`, `workload_b.properties`, `workload_c.properties`, `workload_f.properties`.

Reference từ YCSB built-in (đã có trong image): `/opt/ycsb/workloads/workloada` ... `workloadf`. Có thể override params bằng `-p key=value` hoặc viết file properties riêng để giữ config rõ ràng.

Tham số chính:
```properties
recordcount=1000000
operationcount=1000000
workload=site.ycsb.workloads.CoreWorkload
readallfields=true
readproportion=0.5
updateproportion=0.5
scanproportion=0
insertproportion=0
requestdistribution=zipfian
threadcount=16
```

### 3.2 Run scripts trong `ycsb/scripts/`

Wrapper shell scripts cho từng DB. Ví dụ `run_mongodb.sh`:

```bash
#!/bin/bash
# Usage: ./run_mongodb.sh <workload_letter> <run_number>
# Example: ./run_mongodb.sh a 1
WORKLOAD=$1
RUN=$2
LOG_DIR=../analysis/results/raw_logs

# Load phase (only run once per workload, or before run phase if data cleared)
docker run --rm --network=ycsb-mongo-rs-net ycsb-runner:0.17.0 \
  load mongodb -P /opt/ycsb/workloads/workload${WORKLOAD} \
  -p mongodb.url="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/ycsb?replicaSet=ycsb-rs" \
  -p mongodb.writeConcern=majority \
  -p recordcount=1000000 -p threadcount=16 \
  > $LOG_DIR/log_mongodb_${WORKLOAD}_load.txt 2>&1

# Run phase
docker run --rm --network=ycsb-mongo-rs-net ycsb-runner:0.17.0 \
  run mongodb -P /opt/ycsb/workloads/workload${WORKLOAD} \
  -p mongodb.url="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/ycsb?replicaSet=ycsb-rs" \
  -p mongodb.writeConcern=majority \
  -p recordcount=1000000 -p operationcount=1000000 -p threadcount=16 \
  > $LOG_DIR/log_mongodb_${WORKLOAD}_run${RUN}.txt 2>&1
```

Tương tự cho Cassandra (`docker run ... cassandra-cql -p hosts=cass1,cass2,cass3 -p cassandra.keyspace=ycsb`) và CockroachDB (`docker run ... jdbc -p db.driver=org.postgresql.Driver -p db.url=jdbc:postgresql://crdb1:26257/ycsb?sslmode=disable -p db.user=root`).

### 3.3 Fault tolerance script

`run_fault_tolerance.sh` — kịch bản:
1. Bắt đầu YCSB run phase background
2. Sau 30 giây, `docker stop ycsb-mongoN` (hoặc cassN/crdbN tương ứng)
3. Đo throughput trước và sau khi node fail
4. `docker start` lại node, đo recovery time

### 3.4 Naming convention log files (đã agreed)

- `log_<db>_<workload>_<run>.txt` — ví dụ `log_mongodb_a_run1.txt`
- DB tags: `mongodb`, `cassandra`, `cockroachdb` (lowercase, full)
- Workload tags: `a`, `b`, `c`, `f` (lowercase)
- Fault tolerance: `log_<db>_<workload>_fault.txt`
- Scalability: `log_<db>_<workload>_<N>node.txt` (N=1,2,3)

---

## Files quan trọng trong repo

- `README.md` — Quick start
- `docs/DEVELOPMENT_LOG.md` — **Đọc file này nếu cần chi tiết kỹ thuật** (lỗi đã gặp, design decisions, baseline numbers)
- `docs/HANDOFF.md` — File bạn đang đọc
- `docker/mongodb/docker-compose.yml` — MongoDB cluster definition
- `docker/cassandra/docker-compose.yml` — Cassandra cluster definition
- `docker/cockroachdb/docker-compose.yml` — CockroachDB cluster definition
- `docker/ycsb-runner/Dockerfile` — YCSB runner image

File gốc đề tài (không trong repo, nhưng Quốc giữ riêng): `PROMPT_Do_an_YCSB.md` — chứa references đầy đủ + cấu trúc báo cáo UIT.

---

## Khi cần debug

1. **Đọc `docs/DEVELOPMENT_LOG.md`** section "Errors Encountered & Fixes" trước
2. Kiểm tra trạng thái container: `docker ps` và `docker compose ps`
3. Đọc log: `docker logs ycsb-<name> --tail 50`
4. Verify network: `docker network ls` (phải có `ycsb-mongo-rs-net`, `ycsb-cass-cluster-net`, `ycsb-crdb-cluster-net`)
5. Verify image runner: `docker images ycsb-runner` (phải có tag `0.17.0`)

## Khi cần re-build hoặc reset

```bash
# Reset 1 cluster (xóa data, giữ image)
cd docker/<db>
docker compose down -v
docker compose up -d

# Rebuild ycsb-runner image
cd docker/ycsb-runner
docker build -t ycsb-runner:0.17.0 .
```

---

## Lời khuyên cho người tiếp tục

- **Đừng skip verify step** sau mỗi thay đổi. Pipeline phân tán có nhiều moving parts, sai 1 chỗ ảnh hưởng dây chuyền.
- **Paste output đầy đủ** khi hỏi AI assistant. Một số lỗi chỉ rõ ràng ở dòng cuối stack trace.
- **Test với recordcount nhỏ** (100-1000) trước khi chạy 1M. Tiết kiệm rất nhiều thời gian debug.
- **Stop cluster khi không dùng** (`docker compose stop`). 3 cluster idle ăn ~8GB RAM.
- **KHÔNG dùng `docker compose down -v`** trừ khi muốn reset hoàn toàn — flag `-v` xóa volume.

---

**File last updated**: Phase 2 complete (3 cluster + YCSB pipeline verified, end-to-end smoke test passed for all 3 DBs)
