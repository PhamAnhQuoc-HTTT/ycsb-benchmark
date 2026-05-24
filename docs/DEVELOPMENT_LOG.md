# Development Log — YCSB Benchmark Project

> Nhật ký kỹ thuật chi tiết quá trình xây dựng infrastructure cho đồ án YCSB benchmark.
> File này dùng làm **nguyên liệu cho Chương 3 (Phương pháp & Thiết kế thực nghiệm)** và **Phụ lục B (Hướng dẫn tái tạo)** của báo cáo cuối kỳ.

**Project**: Đánh giá hiệu năng MongoDB / Cassandra / CockroachDB qua YCSB
**Trường**: UIT - VNU-HCM
**Nhóm**: Phạm Anh Quốc (23521307), Trần Thanh Huy (23520649)
**GVHD**: ThS. Nguyễn Hồ Duy Trí

---

## Bối cảnh thiết bị

Toàn bộ infrastructure được dựng trên máy cá nhân của Quốc:

- **OS**: Windows 11 (host) + WSL2 (Ubuntu kernel cho Docker)
- **RAM**: 24GB total, cấp 16GB cho WSL2 qua `.wslconfig`
- **CPU**: 8 logical cores
- **Storage**: SSD, ổ D dành riêng cho project

Một số project khác đang chạy song song (project SE104 — Next.js + PostgreSQL) nên RAM headroom cho benchmark là ~14-15GB sau khi trừ Windows + apps.

---

## Phase 0 — Environment Setup

### 0.1 Docker Desktop + WSL2 RAM config

**Vấn đề ban đầu**: Mặc định Docker Desktop trên Windows chỉ cấp ~2GB RAM cho WSL2 (`Total Memory: 1.9GiB` trong `docker info`). Không đủ chạy Cassandra 3-node (mỗi node cần ~2GB).

**Giải pháp**: Tạo file `~/.wslconfig`:

```ini
[wsl2]
memory=16GB
processors=8
swap=4GB
```

Sau khi tạo, chạy `wsl --shutdown` rồi khởi động lại Docker Desktop. Verify:

```powershell
docker info | Select-String "Total Memory"
# Expected: Total Memory: 15.62GiB (16GB - overhead)
```

**Lưu ý**: Nếu để mặc định 1.9GB, Cassandra sẽ OOM ngay khi bootstrap node thứ 2. Đây là bước **bắt buộc** trước khi pull images.

### 0.2 Java 11 + JAVA_HOME

**Vấn đề**: Máy đã có Java 23 (Oracle JDK) cài sẵn. YCSB 0.17.0 release 2023, code dùng nhiều API cũ + `sun.misc.Unsafe` đã bị restrict trong Java 17+. Java 23 chạy YCSB sẽ ra cảnh báo `Illegal reflective access` và một số binding (HBase, Accumulo) crash.

**Giải pháp**: Cài Java 11 (Eclipse Temurin) song song qua winget:

```powershell
winget install EclipseAdoptium.Temurin.11.JDK
```

Sau khi cài, Temurin tự đẩy lên đầu PATH → `java -version` mặc định = Java 11. Java 23 vẫn ở `C:\Program Files\Java\jdk-23\` cho project khác dùng.

Set `JAVA_HOME` permanent (User scope):

```powershell
[System.Environment]::SetEnvironmentVariable('JAVA_HOME',
  'C:\Program Files\Eclipse Adoptium\jdk-11.0.31.11-hotspot', 'User')
```

YCSB script đọc `JAVA_HOME` để biết JVM ở đâu — không set là YCSB sẽ fail.

### 0.3 Python 3.11

Máy có sẵn Python 3.13.13 (Microsoft Store). PySpark 3.5 + một số thư viện data science chưa support Python 3.13 chính thức. Cài thêm Python 3.11.9 qua winget:

```powershell
winget install Python.Python.3.11
```

Khi tạo virtualenv cho analysis sau này:

```powershell
py -3.11 -m venv .venv
```

→ venv khoá Python 3.11, không phụ thuộc default.

### 0.4 YCSB 0.17.0 binary (local)

Tải binary tar.gz từ GitHub (675MB):

```powershell
Invoke-WebRequest -Uri "https://github.com/brianfrankcooper/YCSB/releases/download/0.17.0/ycsb-0.17.0.tar.gz" `
  -OutFile "$env:USERPROFILE\Downloads\ycsb-0.17.0.tar.gz"
tar -xzf "$env:USERPROFILE\Downloads\ycsb-0.17.0.tar.gz" -C "$env:USERPROFILE\"
```

**Lưu ý quan trọng**: YCSB có 2 launcher scripts:
- `bin/ycsb` — Bash + Python 2 (cho Linux/Mac)
- `bin/ycsb.bat` — Windows batch, có Python 3 fallback (dùng trên Windows native)

→ Trên Windows, **không cần cài Python 2**. YCSB binary local chỉ dùng cho dev/learning; benchmark thật chạy qua Docker.

---

## Phase 1 — Repo Structure

### 1.1 Folder layout

Quyết định: dùng `D:\UIT\Projects\ycsb-benchmark\` (ổ D, không phải C, tránh Windows disk pressure).

Cấu trúc:

```
ycsb-benchmark/
├── docker/{mongodb,cassandra,cockroachdb,ycsb-runner}/
├── ycsb/{workloads,scripts}/
├── analysis/{notebooks,results/{raw_logs,summary,figures}}/
├── docs/
├── report/{drafts,figures,references}/
└── README.md, .gitignore
```

13 folders + 2 file root + 13 `.gitkeep` files để Git track empty folders.

### 1.2 GitHub repo

Cài GitHub CLI:

```powershell
winget install GitHub.cli
gh auth login   # Login via web browser, HTTPS protocol
gh repo create ycsb-benchmark --public --source=. --remote=origin --push \
  --description "YCSB benchmark - MongoDB vs Cassandra vs CockroachDB"
```

Repo: https://github.com/PhamAnhQuoc-HTTT/ycsb-benchmark

### 1.3 .gitignore quan trọng

Loại trừ:
- `docker/*/data/`, `docker/*/logs/` — volume data
- `ycsb-0.17.0/` — binary local
- `analysis/results/raw_logs/*` (giữ `.gitkeep`) — log thô lớn
- `.venv/`, `__pycache__/`, `.ipynb_checkpoints/` — Python
- `.vscode/`, `.idea/` — IDE local

---

## Phase 2 — Database Clusters

### 2.1 MongoDB Replica Set 3-node

**Topology**: 1 PRIMARY (cao priority hơn) + 2 SECONDARY, masterless failover qua Raft-like election.

**Image**: `mongo:7.0` (~800MB)

**Design điểm**:
- 3 container với hostname `mongo1/2/3`, port internal 27017
- Map host: 27017/27018/27019 — tiện debug từ Windows
- Network bridge `ycsb-mongo-rs-net`
- Resource limit mỗi node: 2GB RAM, 2 CPU
- Auth disabled (benchmark env, không phải production)
- Healthcheck: `mongosh ping` mỗi 10s

**Lệnh quan trọng**:

Khởi tạo replica set (chỉ làm 1 lần, sau khi 3 node healthy):

```javascript
rs.initiate({
  _id: 'ycsb-rs',
  members: [
    { _id: 0, host: 'mongo1:27017', priority: 2 },
    { _id: 1, host: 'mongo2:27017', priority: 1 },
    { _id: 2, host: 'mongo3:27017', priority: 1 }
  ]
})
```

**Lưu ý critical**: Member dùng `hostname:port` (không phải IP) vì IP container có thể đổi khi restart.

**Thời gian bootstrap**: ~30 giây cho 3 node healthy + ~15 giây election.

### 2.2 Cassandra Cluster 3-node

**Topology**: Masterless ring với gossip protocol, RF=3 (mỗi data replicate 3 lần).

**Image**: `cassandra:4.1` (~370MB)

**Design điểm**:
- 3 container với hostname `cass1/2/3`, port CQL 9042
- Map host: 9042/9043/9044
- Snitch: `GossipingPropertyFileSnitch` (chuẩn cho multi-DC, cho project thì DC=dc1, rack=rack1)
- **Tất cả 3 node là seed**: `CASSANDRA_SEEDS=cass1,cass2,cass3` — đơn giản, đủ cho 3-node lab
- Heap: `MAX_HEAP_SIZE=1G`, `HEAP_NEWSIZE=200M` — bỏ trống là Cassandra tự lấy 2G heap → OOM trong container 2G limit
- **Bootstrap tuần tự** qua `depends_on: service_healthy`: cass1 → cass2 → cass3

**Tại sao serialize bootstrap?** Cassandra cần seed đang chạy để gossip. Nếu 3 node parallel, gossip conflict → 1 trong 3 stuck ở JOINING state.

**Thời gian bootstrap**: cass1 ~79s, cass2 ~99s, cass3 ~99s → tổng cluster ready sau ~5 phút.

**Verify cluster sau khi `up -d`**:

```bash
docker exec ycsb-cass1 nodetool status
```

Mong đợi 3 dòng bắt đầu `UN` (Up + Normal). Nếu thấy `UJ` (Joining) → đợi thêm 30s.

### 2.3 CockroachDB Cluster 3-node

**Topology**: Distributed SQL với Raft consensus per range (~512MB mỗi range). Mọi range replicate 3 lần.

**Image**: `cockroachdb/cockroach:v23.2.4` (~565MB)

**Design điểm**:
- 3 container với hostname `crdb1/2/3`, port SQL/RPC 26257, Admin UI 8080
- Map host: 26257/26258/26259 (SQL) + 8080/8081/8082 (UI)
- `--insecure` mode (không TLS, đủ cho benchmark env)
- `--join=crdb1:26257,crdb2:26257,crdb3:26257` — list peer
- `--listen-addr=crdbN:26257` — bind cụ thể hostname (không phải 0.0.0.0)
- `--http-addr=0.0.0.0:8080` — Admin UI listen mọi interface
- `--cache=512MiB`, `--max-sql-memory=512MiB` — giới hạn memory trong 2G container
- **Bootstrap parallel** (không cần `depends_on`)
- **Sau khi up, BẮT BUỘC chạy `cockroach init`**

**Tại sao parallel được?** Khác Cassandra: node CockroachDB start xong chỉ wait passive, không cần peer ready. Chỉ khi gọi `init` thì cluster mới form.

**Lệnh init critical**:

```bash
docker exec ycsb-crdb1 cockroach init --insecure --host=crdb1:26257
```

**Phải có `--host=crdb1:26257`** vì `--listen-addr=crdb1:26257` nên `localhost:26257` không listen. Default `cockroach init` connect `localhost:26257` → connection refused.

**Thời gian**: 3 node start parallel ~20s + init 5s.

### 2.4 YCSB Runner Image (Dockerized)

Đây là quyết định thiết kế quan trọng nhất của Phase 2 — sẽ trình bày trong **Chương 3.1 Phương pháp** của báo cáo.

**Vấn đề ban đầu (Cách B đã thử và bỏ)**:

Chạy YCSB từ Windows host kết nối tới MongoDB replica set qua `localhost:27017,localhost:27018,localhost:27019`:

```
com.mongodb.MongoTimeoutException: Timed out after 30000 ms
servers=[{address=mongo1:27017, exception=UnknownHostException: mongo1},
        {address=mongo2:27017, exception=UnknownHostException: mongo2},
        {address=mongo3:27017, exception=UnknownHostException: mongo3}]
```

**Nguyên nhân (Server Discovery and Monitoring - SDAM)**:
1. Driver connect `localhost:27017` ✓
2. Hỏi PRIMARY: "members là ai?"
3. PRIMARY trả `[mongo1:27017, mongo2:27017, mongo3:27017]` (hostname set khi `rs.initiate`)
4. Driver thử connect `mongo1:27017` từ Windows host → DNS fail (hostname chỉ tồn tại trong Docker network)

**Các fix đã loại trừ**:
- Sửa Windows hosts file (`mongo1 → 127.0.0.1` v.v.): không work vì cả 3 hostname đều resolve cùng port 27017, driver tưởng đã connect 3 node nhưng thực ra chỉ 1
- Reconfig rs.config dùng `localhost:port`: phá Docker internal communication giữa 3 node → replication broken

**Giải pháp đúng (Cách A — implemented)**: Đóng gói YCSB trong Docker container, join cùng network với DB. Khi đó YCSB resolve hostname qua Docker DNS internal — natively.

**Lợi ích**:
- Reproducible: clone repo + build image, chạy được ngay, không cần config hosts file
- Đúng pattern academic paper YCSB benchmark
- Dùng được cho cả 3 DB (chỉ đổi `--network=` khác nhau)
- Không có port-mapping NAT overhead → số liệu chính xác hơn

**Dockerfile design**:
- Base: `eclipse-temurin:11-jdk-jammy` (match Java 11 local)
- Install: `python2` (cho ycsb script), `curl`, `ca-certificates`
- Download YCSB 0.17 từ GitHub (~675MB)
- Add PostgreSQL JDBC driver 42.7.3 vào `/opt/ycsb/jdbc-binding/lib/` (cho CockroachDB benchmark)
- `ENTRYPOINT ["ycsb"]` — gọi `docker run ycsb-runner:0.17.0 load mongodb ...` thẳng

**Image size**: 908MB content, 2.14GB disk.

**Build time**: ~24 phút lần đầu (tải YCSB chiếm phần lớn). Lần sau nhờ Docker cache, chỉ rebuild step thay đổi.

---

## Errors Encountered & Fixes

Mỗi lỗi đáng học hỏi, sẽ trình bày trong báo cáo phần **Limitations / Lessons Learned**.

### Error 1: Cassandra `oplog.rs not found` warning trước khi `rs.initiate()`

**Triệu chứng**: Log mongo1 có dòng warning mỗi giây:
```
"Collection [local.oplog.rs] not found"
"ReadConcernMajorityNotAvailableYet"
```

**Nguyên nhân**: MongoDB start với `--replSet ycsb-rs` mong đợi là replica set member, nhưng `rs.initiate()` chưa được gọi → oplog chưa tồn tại → FTDC monitoring fail.

**Fix**: Chạy `rs.initiate()`. Warning biến mất ngay sau khi cluster form.

### Error 2: YCSB UnknownHostException khi connect từ Windows host

Đã trình bày chi tiết trong section 2.4.

### Error 3: JDBC binding NullPointerException

**Triệu chứng**:
```
docker run --rm ycsb-runner:0.17.0 shell jdbc
> Exception in thread "main" java.lang.NullPointerException
        at site.ycsb.db.JdbcDBClient.init(JdbcDBClient.java:187)
```

**Nguyên nhân kép**:
1. PostgreSQL JDBC driver không có sẵn trong YCSB 0.17 (jdbc-binding chỉ có skeleton API)
2. `JdbcDBClient.init()` cần `db.url`, `db.driver`, `db.user` — smoke test `shell jdbc` không cung cấp

**Fix**:
- Add PostgreSQL JDBC driver 42.7.3 vào Dockerfile (step `curl ... pgjdbc download`)
- Khi chạy benchmark thật, cung cấp đủ params:
  ```
  -p db.driver=org.postgresql.Driver
  -p db.url=jdbc:postgresql://crdb1:26257/ycsb?sslmode=disable
  -p db.user=root
  -p db.passwd=""
  ```

### Error 4: `cockroach init` connection refused

**Triệu chứng**:
```
docker exec ycsb-crdb1 cockroach init --insecure
warning: node not ready... dial tcp [::1]:26257: connect: connection refused
```

**Nguyên nhân**: `cockroach init` default connect `localhost:26257`. Nhưng cluster start với `--listen-addr=crdb1:26257` (bind hostname cụ thể, không phải 0.0.0.0) → `localhost` không listen.

**Fix**: Thêm `--host=crdb1:26257`:
```bash
docker exec ycsb-crdb1 cockroach init --insecure --host=crdb1:26257
```

Tất cả lệnh `cockroach sql/node status` về sau cũng cần `--host`.

### Error 5: Docker layer cache invalidation khi update Dockerfile

**Triệu chứng**: Rebuild ycsb-runner image sau khi thêm PostgreSQL driver — tưởng cache hit, mất 1-2 phút. Thực tế mất 24 phút (tải lại YCSB 675MB).

**Nguyên nhân**: Mình (Claude) viết lại Dockerfile, gộp `RUN apt-get` và `RUN ln -s` thành 1 RUN → hash layer thay đổi → tất cả layer phía sau invalidate.

**Lesson learned**: Khi update Dockerfile có caching, **chỉ thêm step mới ở cuối**, không bao giờ gộp/sửa layer cũ trừ khi thực sự cần thiết.

---

## Smoke Test Results

100 records, 4 threads, mục đích **chỉ verify pipeline**, không phản ánh hiệu năng thực:

| DB | Throughput (ops/sec) | Avg INSERT (µs) | p95 (µs) | p99 (µs) | Return |
|----|---------------------|-----------------|----------|----------|--------|
| MongoDB | 112.87 | 14,664 | 13,495 | 152,063 | OK 100/100 |
| Cassandra | 26.40 | 14,499 | 24,255 | 81,983 | OK 100/100 |
| CockroachDB | 200.00 | 8,810 | 11,263 | 39,807 | OK 100/100 |

**Quan sát sơ bộ** (sẽ verify lại ở Phase 4 với 1M records):

- CockroachDB nhanh nhất ở sample này — JDBC batchsize=100 giúp gộp insert thành 1 round-trip Raft
- Cassandra throughput thấp do startup overhead (JVM warmup, cluster discovery, prepared statement). Khi data lớn, Cassandra thường vượt MongoDB ở write-heavy
- MongoDB `writeConcern=majority` thêm latency vì phải đợi 2/3 node confirm

**Lưu ý cho Chương 4 báo cáo**: KHÔNG dùng số liệu smoke test làm kết luận. Sample 100 quá nhỏ → JVM warmup chưa xong → không đại diện.

---

## Resource Footprint khi cluster idle

Đo với `docker stats --no-stream`:

| Cluster | RAM mỗi node | Tổng RAM |
|---------|--------------|----------|
| MongoDB (3 node) | ~400-600 MiB | ~1.5 GiB |
| Cassandra (3 node) | ~1.4-1.6 GiB | ~4.5 GiB |
| CockroachDB (3 node) | ~600-800 MiB | ~2 GiB |

Nếu chạy đồng thời 3 cluster: ~8 GiB. Còn ~7 GiB headroom trong 15.62 GiB WSL2 allocation — đủ cho YCSB benchmark workload thật.

**Khuyến nghị khi chạy benchmark Phase 4**: Stop 2 cluster không dùng, chỉ chạy 1 cluster tại 1 thời điểm để có RAM headroom max.

---

## Stop / Restart Behavior

`docker compose stop` vs `docker compose down -v`:

| Lệnh | Container | Volume | Network |
|------|-----------|--------|---------|
| `stop` | Stopped, giữ lại | Giữ data | Giữ |
| `down` (không `-v`) | Removed | Giữ data | Removed |
| `down -v` | Removed | **XÓA** | Removed |

→ Dùng `stop`/`start` cho daily work. Chỉ dùng `down -v` khi muốn reset hoàn toàn (chạy benchmark mới).

**Restart behavior**:
- MongoDB: `start` xong, replica set config còn nguyên trong volume → cluster sống lại trong ~30s
- Cassandra: `start` mất ~3-5 phút (gossip phải re-sync)
- CockroachDB: `start` ~30s, không cần init lại

---

## Git History (Phase 0-2)

```
fe8cb42  feat(cockroachdb): add 3-node cluster with Raft consensus
a03c42b  feat(cassandra): add 3-node cluster with GossipingPropertyFileSnitch
f21ecfb  docs: remove status section from README
1c63681  feat(mongodb): add 3-node replica set + dockerized YCSB runner
2b2ee8b  Fix formatting in README.md for repo structure
df1611c  chore: initial repo structure for YCSB benchmark project
```

Convention: `<type>(<scope>): <subject>` theo Conventional Commits.

---

## Next Steps (Phase 3+)

### Huy: YCSB workload + run scripts

1. Tạo `ycsb/workloads/workload_a.properties`, `workload_b.properties`, `workload_c.properties`, `workload_f.properties` — tham số recordcount, operationcount, threadcount thống nhất giữa 3 DB
2. Viết `ycsb/scripts/run_mongodb.sh`, `run_cassandra.sh`, `run_cockroachdb.sh` — wrap lệnh `docker run --network=... ycsb-runner load/run` cho từng DB
3. Viết `ycsb/scripts/run_fault_tolerance.sh` — kịch bản dừng 1 node giữa benchmark

### Quốc (sau khi Huy xong scripts): Benchmark Phase 4

Chạy 4 workload × 3 DB × 3 runs = 36 benchmark runs với recordcount=1M.

Ước tính thời gian: ~25-35 giờ chạy thuần (mỗi run 30-60 phút tùy DB).

### Quốc: Analysis Phase 5

`analysis/parse_logs.py` — đọc log YCSB → CSV summary
`analysis/visualize.py` — vẽ biểu đồ throughput (grouped bar), latency p50/p95/p99 (line/bar), scalability (line)

---

## References cho báo cáo

Khi viết Chương 3, các references nên cite:

- **YCSB paper**: Cooper et al., "Benchmarking cloud serving systems with YCSB," SoCC 2010 — cite ở Section 3.1 (lý do chọn YCSB)
- **Docker docs**: Compose networking, resource limits — cite ở Section 3.2 (môi trường thực nghiệm)
- **MongoDB docs**: Replica Set architecture — Section 3.3
- **Cassandra docs**: GossipingPropertyFileSnitch, RF, consistency level — Section 3.3
- **CockroachDB docs**: Architecture overview, Raft layer — Section 3.3

Đường link đầy đủ trong `PROMPT_Do_an_YCSB.md` ở root project (file gốc của đề tài).

---

# PHASE 4 — BENCHMARK & FAULT TOLERANCE (bổ sung)

> Phần này append vào DEVELOPMENT_LOG.md hiện có, ghi lại Phase 4 (thu thập dữ liệu).

## 4.1 Cấu hình benchmark

- recordcount = 1,000,000 (1M records, mỗi record 10 field × 100 byte ≈ 1KB)
- operationcount = 1,000,000
- threadcount = 16
- runs = 3 (mỗi workload chạy 3 lần lấy trung bình)
- requestdistribution = zipfian
- Workloads: A (50/50 read/update), B (95/5), C (100% read), F (50/50 read/read-modify-write)

Mỗi DB chạy tuần tự (stop 2 DB còn lại + SE104 để giải phóng RAM, tránh resource contention).

## 4.2 Lỗi #6 — Cassandra load chỉ đạt 938K/1M (write timeout)

**Hiện tượng**: Lần load Cassandra đầu tiên, YCSB report `[INSERT], Return=OK, 753323` (thiếu ~247K). Verify bằng `nodetool tablestats` cho thấy thực tế có ~938K partitions.

**Nguyên nhân**: Với threadcount=16, Cassandra dưới tải ghi cao bị write timeout (default `write_request_timeout_in_ms = 2000ms`). Insert timeout không được đếm vào Return=OK.

**Cách fix**: Tăng write timeout runtime trên cả 3 node (không cần restart):
```bash
docker exec ycsb-cass1 nodetool settimeout write 10000
docker exec ycsb-cass2 nodetool settimeout write 10000
docker exec ycsb-cass3 nodetool settimeout write 10000
```
Sau đó TRUNCATE + load lại → đạt đủ 1,000,000 (verify: 1,006,650 partitions estimate).

**LƯU Ý QUAN TRỌNG cho reproducibility**: `nodetool settimeout` chỉ có hiệu lực runtime — mất khi container restart. Để tái tạo, cần chạy lại 3 lệnh trên SAU mỗi lần start cluster Cassandra, TRƯỚC khi load. (Cải tiến tương lai: set `write_request_timeout_in_ms` trong cassandra.yaml qua docker-compose.)

## 4.3 Kết quả Throughput (ops/sec, trung bình 3 runs)

| Workload | MongoDB | Cassandra | CockroachDB |
|----------|--------:|----------:|------------:|
| A (50/50) | 941.82 | 4010.62 | 1019.33 |
| B (95/5) | 3822.53 | 3418.69 | 2514.14 |
| C (100% read) | 6405.01 | 3347.35 | 3841.68 |
| F (RMW) | 892.47 | 2258.19 | 770.67 |

Độ biến thiên (CV = std/mean): hầu hết < 7%, riêng Cassandra B/C ~11-13% (biến động cache đọc). Không có outlier.

**Phân tích:**
- Cassandra mạnh ghi (A, F) — LSM-tree append-only.
- MongoDB mạnh đọc (B, C) — B-tree + WiredTiger cache.
- CockroachDB ổn định nhất (CV ~2%) nhưng throughput vừa phải — overhead Raft consensus cho strong consistency.

## 4.4 Fault tolerance test

Script `run_fault_tolerance.sh <db>`: chạy workload A với flag `-s` (throughput mỗi 10s), dừng 1 node sau 30s, khởi động lại sau 60s.

| | MongoDB | Cassandra | CockroachDB |
|--|---------|-----------|-------------|
| Node dừng | mongo3 (SECONDARY) | cass3 | crdb3 |
| Operation fail | Không | Không | **UPDATE-FAILED** (lúc re-elect leader) |
| Throughput thấp nhất | ~490 | ~1100 | ~401 |
| Latency spike | 5-7s | ~2s | ~4s |
| CAP | CP-leaning | AP | CP (strict) |

**Quan sát chính:**
- MongoDB: PRIMARY vẫn phục vụ khi mất SECONDARY (writeConcern=majority cần 2/3). Khi node rejoin, throughput tụt mạnh do oplog catch-up.
- Cassandra: không downtime, không operation fail — RF=3 + CL=ONE cho phép phục vụ với 2/3 node. AP điển hình.
- CockroachDB: xuất hiện UPDATE-FAILED trong vài giây đầu khi Raft re-elect leader cho các range có leader ở node bị dừng. CP nghiêm ngặt.

## 4.5 Tổng kết Phase 4

- 36 benchmark logs (3 DB × 4 WL × 3 runs) + 3 load logs
- 3 fault tolerance logs + 3 events logs
- parse_logs.py → summary_raw.csv (36 dòng) + summary_mean.csv (12 dòng)
- Toàn bộ data verified (đủ 1M mỗi DB, mean = avg(raw), không null/outlier)

Thời gian chạy thực tế: MongoDB ~2.5h, Cassandra ~1h (sau khi fix), CockroachDB ~2.7h.

Tổng số commit Phase 3-4: ~8 commit, linear history.
