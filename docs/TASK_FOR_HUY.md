# TASK_FOR_HUY — Việc cần làm cho phần Trần Thanh Huy

> File này dành riêng cho Huy. Đọc hết một lượt, rồi dùng phần "PROMPT CHO AI" ở cuối để paste vào ChatGPT/Claude khi cần trợ giúp code.

---

## Bối cảnh nhanh

Quốc đã làm xong toàn bộ phần thu thập dữ liệu:
- 3 cluster Docker (MongoDB, Cassandra, CockroachDB), mỗi cái 3 node
- Benchmark đầy đủ: 3 DB × 4 workload (A/B/C/F) × 3 lần chạy = 36 runs, mỗi run 1 triệu records
- Fault tolerance test cho cả 3 DB (dừng 1 node giữa chừng)
- Đã parse ra 2 file CSV trong `analysis/results/summary/`

**Việc của Huy gồm 3 phần:**
1. Vẽ biểu đồ (visualize) từ CSV
2. Phân tích kết quả + viết Chương 4.4 (so sánh)
3. Viết Chương 2 (lý thuyết 3 hệ thống)

---

## DỮ LIỆU ĐẦU VÀO

### File 1: `analysis/results/summary/summary_mean.csv` (12 dòng)
Trung bình 3 runs cho mỗi (db, workload). Đây là file CHÍNH để vẽ biểu đồ.

Các cột quan trọng:
- `db` — mongodb / cassandra / cockroachdb
- `workload` — a / b / c / f
- `throughput_ops_sec` — throughput trung bình (số liệu chính)
- `throughput_std` — độ lệch chuẩn (dùng làm error bar)
- `throughput_min`, `throughput_max` — min/max của 3 runs
- `read_p95_us`, `read_p99_us` — latency đọc (microseconds)
- `update_p95_us`, `update_p99_us` — latency ghi (microseconds)
- `read_modify_write_p95_us`, `read_modify_write_p99_us` — latency RMW (chỉ workload f)

> Lưu ý: latency đơn vị **microseconds (us)**. Chia 1000 để ra milliseconds (ms) cho dễ đọc trên biểu đồ.

### File 2: `analysis/results/summary/summary_raw.csv` (36 dòng)
Từng run riêng lẻ (run 1, 2, 3). Dùng nếu muốn vẽ box plot hoặc thể hiện độ biến thiên.

### File 3: Fault tolerance logs (cho biểu đồ timeline)
3 file trong `analysis/results/<db>/log_<db>_a_fault.txt`:
- `analysis/results/mongodb/log_mongodb_a_fault.txt`
- `analysis/results/cassandra/log_cassandra_a_fault.txt`
- `analysis/results/cockroachdb/log_cockroachdb_a_fault.txt`

Mỗi file chứa các dòng throughput theo thời gian (mỗi 10 giây), format:
```
... 10 sec: 6264 operations; 626.34 current ops/sec; ...
... 19 sec: 13292 operations; 702.94 current ops/sec; ...
```
→ Cần parse cặp `(số giây, current ops/sec)` để vẽ đường throughput theo thời gian.

File events (mốc dừng/khởi động node): `analysis/results/<db>/log_<db>_fault_events.txt`
```
[... 15:31:34] STOP node ycsb-crdb3 (fault injection)
[... 15:32:36] START node ycsb-crdb3 (recovery)
```
→ Dùng để vẽ đường dọc đánh dấu thời điểm node down/up trên biểu đồ timeline.

---

## PHẦN 1 — VISUALIZE (ưu tiên cao nhất)

Tạo file `analysis/visualize.py` (hoặc notebook `analysis/notebooks/visualize.ipynb`). Cần 4 biểu đồ:

### Biểu đồ 1: Throughput comparison (QUAN TRỌNG NHẤT)
- **Loại**: grouped bar chart
- **Trục X**: 4 workload (A, B, C, F)
- **Trục Y**: throughput (ops/sec)
- **Nhóm cột**: 3 DB (mongodb, cassandra, cockroachdb) — 3 màu khác nhau
- **Error bar**: dùng `throughput_std`
- **Nguồn**: `summary_mean.csv`
- Mục đích: thấy ngay DB nào mạnh ở workload nào

### Biểu đồ 2: Latency comparison (p95 / p99)
- **Loại**: grouped bar hoặc 2 subplot (p95, p99)
- **Trục X**: 4 workload
- **Trục Y**: latency (ms — nhớ chia 1000 từ us)
- Vẽ cho READ latency (`read_p95_us`, `read_p99_us`)
- Có thể làm thêm bản cho UPDATE latency
- **Nguồn**: `summary_mean.csv`

### Biểu đồ 3: Fault tolerance timeline (cho mỗi DB, hoặc gộp 3 DB)
- **Loại**: line chart (throughput theo thời gian)
- **Trục X**: thời gian (giây, 0 → ~400)
- **Trục Y**: current ops/sec
- **3 đường**: mongodb, cassandra, cockroachdb
- **Đường dọc đánh dấu**: thời điểm node STOP (~giây 30) và node START (~giây 90) — đọc từ events log
- **Nguồn**: parse 3 file `log_<db>_a_fault.txt`
- Mục đích: thấy throughput drop khi node down + recovery — minh chứng CAP

### Biểu đồ 4 (tùy chọn): Heatmap hoặc radar
- So sánh tổng hợp 3 DB qua 4 workload trên 1 hình
- Đẹp cho slide thuyết trình

**Style gợi ý** (đồng bộ với Project Power BI của Quốc): theme tông xanh navy/blue, font rõ ràng, lưu cả `.png` (cho Word) và `.svg` (cho slide). Lưu vào `analysis/results/figures/`.

---

## PHẦN 2 — PHÂN TÍCH KẾT QUẢ (Chương 4.4)

Dựa trên số liệu, viết phân tích so sánh. Các điểm chính đã thấy trong data:

**Throughput:**
- Cassandra thắng workload ghi nhiều: A (4011 vs MongoDB 942 — gấp 4.3 lần), F (2258 vs 893 — gấp 2.5 lần). Giải thích: LSM-tree ghi tuần tự (append-only), không update tại chỗ.
- MongoDB thắng workload đọc nhiều: C (6405 vs Cassandra 3347 — gấp 1.9 lần), B (3823). Giải thích: B-tree index + WiredTiger cache đọc nhanh.
- CockroachDB throughput thấp/vừa nhưng ổn định nhất (độ lệch chuẩn nhỏ nhất). Giải thích: mỗi ghi là 1 distributed transaction qua Raft consensus → overhead nhất quán, đổi lấy ACID.

**Fault tolerance (CAP trade-off — phần đắt giá nhất):**
- MongoDB: dừng SECONDARY → PRIMARY vẫn phục vụ (writeConcern=majority cần 2/3). Latency update spike 5-7s. Nghiêng CP.
- Cassandra: dừng 1 node → vẫn phục vụ bình thường (RF=3, CL=ONE), không operation nào fail, chỉ tăng latency ~2s. Đây là AP điển hình.
- CockroachDB: dừng 1 node → có UPDATE-FAILED trong lúc Raft re-elect leader, throughput tụt mạnh (~400) rồi phục hồi. CP nghiêm ngặt — thà fail còn hơn ghi không nhất quán.

→ Kết luận: 3 paradigm cho 3 hành vi CAP khác nhau. Gợi ý chọn DB theo loại ứng dụng (đúng như mục tiêu mail gửi thầy).

---

## PHẦN 3 — VIẾT CHƯƠNG 2 (LÝ THUYẾT)

Lý thuyết kiến trúc 3 hệ thống (mỗi cái 1 bảng đặc điểm):
- **MongoDB**: document model, replica set, oplog replication, writeConcern, read preference
- **Cassandra**: column-family, masterless ring, gossip protocol, consistency level (ONE/QUORUM/ALL), LSM-tree + SSTable, RF
- **CockroachDB**: NewSQL, distributed SQL, Raft consensus, range/replica, serializable isolation, MVCC

Liên hệ với CAP theorem: MongoDB & CockroachDB nghiêng CP, Cassandra nghiêng AP. Dẫn chứng bằng kết quả fault tolerance thực nghiệm ở Phần 2.

---

## CÁCH BẮT ĐẦU

```bash
# 1. Clone repo (nếu chưa có)
git clone https://github.com/PhamAnhQuoc-HTTT/ycsb-benchmark.git
cd ycsb-benchmark

# 2. Tạo môi trường Python cho visualize
cd analysis
python -m venv .venv
# Windows:
.venv\Scripts\activate
# Cài thư viện
pip install pandas matplotlib seaborn jupyter

# 3. Mở data xem thử
python -c "import pandas as pd; print(pd.read_csv('results/summary/summary_mean.csv'))"

# 4. Bắt đầu viết visualize.py (xem PROMPT CHO AI bên dưới)
```

Không cần chạy lại Docker hay benchmark — data đã có sẵn trong `analysis/results/`.

---

## PROMPT CHO AI (paste nguyên đoạn dưới vào ChatGPT/Claude)

```
Tôi đang làm đồ án so sánh hiệu năng 3 database phân tán (MongoDB, Cassandra,
CockroachDB) bằng YCSB benchmark. Đồng đội đã chạy benchmark xong và parse ra CSV,
việc của tôi là visualize + phân tích.

Tôi có file analysis/results/summary/summary_mean.csv với các cột:
db, workload, n_runs, throughput_ops_sec, throughput_std, throughput_min,
throughput_max, read_avg_us, read_p95_us, read_p99_us, update_avg_us,
update_p95_us, update_p99_us, read_modify_write_p95_us, read_modify_write_p99_us,
runtime_ms (và một số cột ops khác).

- Có 12 dòng = 3 db (mongodb/cassandra/cockroachdb) × 4 workload (a/b/c/f).
- Workload a = 50/50 read/update, b = 95/5 read/update, c = 100% read,
  f = 50/50 read/read-modify-write.
- Latency đơn vị microseconds (chia 1000 ra ms).

Hãy viết cho tôi file Python visualize.py dùng pandas + matplotlib + seaborn,
tạo các biểu đồ sau và lưu PNG (300 dpi) + SVG vào thư mục results/figures/:

1. Grouped bar chart: throughput theo workload, nhóm theo db, có error bar
   dùng throughput_std. Đây là biểu đồ chính.
2. Grouped bar chart latency: read p95 và p99 theo workload, nhóm theo db (đơn vị ms).
3. (nếu được) thêm biểu đồ update latency p99 tương tự.

Yêu cầu:
- Code rõ ràng, comment tiếng Việt.
- Theme màu chuyên nghiệp (tông xanh navy/blue), font dễ đọc, có title, legend, nhãn trục.
- Mỗi biểu đồ là 1 hàm riêng, gọi trong main().
- Đường dẫn file linh hoạt (dùng pathlib, không hardcode đường dẫn tuyệt đối).

Sau đó hướng dẫn tôi cách parse 3 file log fault tolerance
(analysis/results/<db>/log_<db>_a_fault.txt) để vẽ biểu đồ throughput theo thời gian.
Mỗi file có các dòng dạng:
"... 10 sec: 6264 operations; 626.34 current ops/sec; ..."
Tôi cần lấy cặp (số giây, current ops/sec) từ mỗi dòng để vẽ line chart 3 đường
(3 db), kèm 2 đường dọc đánh dấu thời điểm node bị dừng (~giây 30) và khởi động
lại (~giây 90).
```

---

## NHỮNG ĐIỀU CẦN BIẾT KHI BẢO VỆ

(Để Huy trả lời được khi thầy hỏi về phần benchmark — dù Quốc làm phần này)

- **Tại sao YCSB chạy trong container?** Vì chạy từ Windows host bị lỗi resolve hostname nội bộ của cluster (Docker DNS). Đóng gói YCSB thành container join chung network là cách sạch nhất.
- **Tại sao Cassandra phải tăng write timeout?** Lần load đầu với threadcount=16, một số insert bị timeout (chỉ vào ~938K/1M). Tăng `nodetool settimeout write 10000` (2s → 10s) thì load đủ 1M. Đây cũng là quan sát về độ ổn định write của Cassandra dưới tải cao.
- **Tại sao chọn workload A/B/C/F?** Đây là các workload chuẩn của YCSB: A mixed, B read-heavy, C read-only, F read-modify-write. Bao phủ các pattern phổ biến. (Workload D, E không dùng vì insert-heavy/scan ít phổ biến hơn cho so sánh này.)
- **Mỗi config chạy 3 lần để làm gì?** Lấy trung bình + độ lệch chuẩn, đảm bảo số liệu ổn định, loại nhiễu.
