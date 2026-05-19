# YCSB Benchmark — Distributed Database Performance Evaluation

> Evaluating Big Data Processing Performance of Distributed Database Systems
> (NoSQL and NewSQL) via YCSB Experiments

**Đề tài liên môn**: Cơ sở dữ liệu phân tán + Dữ liệu lớn
**Trường**: Đại học Công nghệ Thông tin — VNU-HCM (UIT)
**GVHD**: ThS. Nguyễn Hồ Duy Trí

## Nhóm thực hiện

| Họ tên | MSSV | Vai trò |
|--------|------|---------|
| Phạm Anh Quốc | 23521307 | Chủ nhiệm — Docker, benchmark, visualization |
| Trần Thanh Huy | 23520649 | Lý thuyết, YCSB scripts, analysis |

## Hệ thống đánh giá

- **MongoDB 7.0** — Document NoSQL
- **Apache Cassandra 4.1** — Column-family NoSQL
- **CockroachDB v23.2.4** — NewSQL distributed SQL

## Kịch bản thực nghiệm

1. **4 workload** (A, B, C, F) trên 3 hệ thống, mỗi WL chạy 3 lần
2. **Scalability test** — Workload A với 1 → 2 → 3 node
3. **Fault tolerance** — Dừng 1 node giữa benchmark, quan sát recovery

## Cấu trúc repo

```
ycsb-benchmark/
├── docker/              # Docker Compose cho 3 hệ thống
│   ├── mongodb/
│   ├── cassandra/
│   └── cockroachdb/
├── ycsb/                # YCSB workloads + run scripts
│   ├── workloads/       # workload_a/b/c/f.properties
│   └── scripts/         # run_*.sh
├── analysis/            # Python phân tích kết quả
│   ├── results/
│   │   ├── raw_logs/    # Log YCSB thô
│   │   ├── summary/     # CSV tổng hợp
│   │   └── figures/     # Biểu đồ PNG/SVG
│   └── notebooks/       # Jupyter notebooks
├── report/              # Báo cáo + tài liệu tham khảo
└── docs/                # Hướng dẫn tái tạo môi trường
```

## Tài liệu nguồn

Bài báo cơ sở:
> E. Dritsas and M. Trigka, "Database Systems in the Big Data Era: Architectures, Performance, and Open Challenges," *IEEE Access*, vol. 13, pp. 95068-95084, 2025.