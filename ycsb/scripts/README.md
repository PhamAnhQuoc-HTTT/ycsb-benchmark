# YCSB Benchmark Scripts

Scripts chạy benchmark cho 3 hệ thống. Mỗi script tự động LOAD dữ liệu rồi RUN tất cả workload.

## File

- `common.sh` — config chung + helper functions (được source bởi các script khác)
- `run_mongodb.sh` — benchmark MongoDB
- `run_cassandra.sh` — benchmark Cassandra
- `run_cockroachdb.sh` — benchmark CockroachDB

## Cách dùng

### Smoke test trước (KHUYẾN NGHỊ — verify pipeline với data nhỏ)

```bash
cd ycsb/scripts
RECORDCOUNT=10000 OPERATIONCOUNT=10000 RUNS=1 THREADCOUNT=4 bash run_mongodb.sh
```

Chỉ load 10K records, chạy mỗi workload 1 lần. Mất ~5 phút. Nếu OK mới chạy full.

### Full benchmark (1M records, 3 runs)

```bash
cd ycsb/scripts
bash run_mongodb.sh       # ~6-10 tiếng
bash run_cassandra.sh     # ~6-10 tiếng
bash run_cockroachdb.sh   # ~8-12 tiếng
```

Tham số mặc định: recordcount=1,000,000, operationcount=1,000,000, threadcount=16, runs=3.

## Tham số override (qua environment variable)

| Biến | Mặc định | Ý nghĩa |
|------|----------|---------|
| `RECORDCOUNT` | 1000000 | Số record load vào DB |
| `OPERATIONCOUNT` | 1000000 | Số operation trong run phase |
| `THREADCOUNT` | 16 | Số thread client đồng thời |
| `RUNS` | 3 | Số lần chạy mỗi workload |
| `IMAGE` | ycsb-runner:0.17.0 | Tên Docker image |

## Workflow chuẩn (chạy tuần tự từng DB)

Vì 3 cluster ăn nhiều RAM, **chạy 1 DB tại 1 thời điểm**:

```bash
# 1. Start DB cần benchmark, stop 2 DB còn lại
cd docker/mongodb && docker compose start
cd ../cassandra && docker compose stop
cd ../cockroachdb && docker compose stop

# 2. (Lần đầu) tạo schema — xem README section 3/4/5

# 3. Chạy benchmark
cd ../../ycsb/scripts
bash run_mongodb.sh

# 4. Khi xong, chuyển sang DB tiếp theo
```

## Output

Logs lưu trong `analysis/results/<db>/`:
- `log_<db>_load.txt` — load phase
- `log_<db>_<workload>_run<N>.txt` — run phase mỗi workload mỗi lần

Ví dụ: `analysis/results/mongodb/log_mongodb_a_run1.txt`

## Lưu ý quan trọng

- **Workload files** (`workload_a/b/c/f.properties`) được mount từ `ycsb/workloads/` vào container lúc runtime. Sửa file đó là thay đổi config benchmark.
- **LOAD chỉ chạy 1 lần** cho mỗi DB (đầu mỗi script). Tất cả workload chạy trên cùng dataset đã load.
- Script tự kiểm tra `Return=OK` và `Throughput` trong log, cảnh báo nếu có vẻ fail.
- Nếu muốn chạy lại từ đầu với data sạch: `docker compose down -v && docker compose up -d`, tạo lại schema, rồi chạy script (script sẽ load lại).
