# 풀 크기 스윕 결과 — peak

생성: 2026-09-25 23:08. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-182532", "pool_sizes": "2", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-183408", "pool_sizes": "5", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-184235", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-185104", "pool_sizes": "20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-185931", "pool_sizes": "40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-190821", "pool_sizes": "2", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-191647", "pool_sizes": "5", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-192514", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-193344", "pool_sizes": "20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-194211", "pool_sizes": "40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| peak1x | 10 | 30000 | 200 | 1 | 1.7 | 1.69 / 0.59 | 50.4 / 32.3 | 53.5 | 55 / 166 | 27 | 0 | 1 | 2 | 14% | 4% | 0.2 | IdleInTx:app 0.1, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790329521000&to=1790329821000) |
| peak1x | 2 | 30000 | 200 | 1 | 1.7 | 1.68 / 0.53 | 60.8 / 35.1 | 54.8 | 55 / 114 | 33 | 0 | 1 | 2 | 14% | 4% | 0.3 | IdleInTx:app 0.2, CPU 0.1, IO:WalSync 0.0 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790328500000&to=1790328800000) |
| peak1x | 20 | 30000 | 200 | 1 | 1.7 | 1.67 / 0.51 | 51.9 / 34.2 | 53.7 | 55 / 222 | 28 | 0 | 2 | 2 | 10% | 4% | 0.1 | IdleInTx:app 0.1, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790330032000&to=1790330332000) |
| peak1x | 40 | 30000 | 200 | 1 | 1.7 | 1.71 / 0.72 | 64.0 / 34.0 | 60.9 | 60 / 227 | 27 | 0 | 2 | 3 | 14% | 4% | 0.2 | IdleInTx:app 0.1, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790330541000&to=1790330841000) |
| peak1x | 5 | 30000 | 200 | 1 | 1.7 | 1.70 / 0.60 | 52.2 / 33.6 | 53.8 | 54 / 253 | 28 | 0 | 1 | 2 | 8% | 4% | 0.2 | IdleInTx:app 0.1, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790329014000&to=1790329314000) |
| peak3x | 10 | 30000 | 200 | 1 | 5.0 | 1.60 / 0.30 | 45.3 / 27.0 | 50.1 | 51 / 302 | 26 | 0 | 1 | 2 | 12% | 6% | 0.4 | IdleInTx:app 0.3, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790332080000&to=1790332380000) |
| peak3x | 2 | 30000 | 200 | 1 | 5.0 | 15.40 / 3.26 | 45.8 / 26.7 | 61.7 | 62 / 397 | 41 | 1 | 2 | 3 | 13% | 6% | 0.4 | IdleInTx:app 0.3, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790331067000&to=1790331367000) |
| peak3x | 20 | 30000 | 200 | 1 | 5.0 | 1.59 / 0.27 | 45.9 / 26.9 | 52.2 | 52 / 230 | 26 | 0 | 2 | 3 | 11% | 6% | 0.5 | IdleInTx:app 0.4, CPU 0.1, IO:WalSync 0.0 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790332592000&to=1790332892000) |
| peak3x | 40 | 30000 | 200 | 1 | 5.0 | 1.57 / 0.27 | 45.3 / 27.4 | 50.2 | 51 / 232 | 25 | 0 | 2 | 3 | 12% | 6% | 0.4 | IdleInTx:app 0.2, CPU 0.1, IO:WalSync 0.0 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790333099000&to=1790333399000) |
| peak3x | 5 | 30000 | 200 | 1 | 5.0 | 1.62 / 0.30 | 44.8 / 26.1 | 49.7 | 51 / 283 | 27 | 0 | 2 | 2 | 11% | 6% | 0.4 | IdleInTx:app 0.3, CPU 0.1, IO:WalSync 0.0 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790331573000&to=1790331873000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **peak1x** (timeout 30000ms, threads 200): 최고 TPS 1.7(pool 2). 규칙1(최고 TPS 98% 이상 최소 풀) = 2, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 2 5%, pool 5 0%, pool 10 0%, pool 20 0%, pool 40 0%
- **peak3x** (timeout 30000ms, threads 200): 최고 TPS 5.0(pool 40). 규칙1(최고 TPS 98% 이상 최소 풀) = 2, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = 20. DB 대기 비중: pool 2 0%, pool 5 3%, pool 10 0%, pool 20 6%, pool 40 1%

## 캡션 초안

- `peak1x-p10-t30000-th200-r1`: 작업자 100명(사이클 60000ms), 풀 10개. 포장 완료 1.7건/s, 커넥션 획득 대기 p95 1.69ms, 점유 p95 50.4ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.1, CPU 0.1.
- `peak1x-p2-t30000-th200-r1`: 작업자 100명(사이클 60000ms), 풀 2개. 포장 완료 1.7건/s, 커넥션 획득 대기 p95 1.68ms, 점유 p95 60.8ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.2, CPU 0.1.
- `peak1x-p20-t30000-th200-r1`: 작업자 100명(사이클 60000ms), 풀 20개. 포장 완료 1.7건/s, 커넥션 획득 대기 p95 1.67ms, 점유 p95 51.9ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.1, CPU 0.1.
- `peak1x-p40-t30000-th200-r1`: 작업자 100명(사이클 60000ms), 풀 40개. 포장 완료 1.7건/s, 커넥션 획득 대기 p95 1.71ms, 점유 p95 64.0ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.1, CPU 0.1.
- `peak1x-p5-t30000-th200-r1`: 작업자 100명(사이클 60000ms), 풀 5개. 포장 완료 1.7건/s, 커넥션 획득 대기 p95 1.70ms, 점유 p95 52.2ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.1, CPU 0.1.
- `peak3x-p10-t30000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 10개. 포장 완료 5.0건/s, 커넥션 획득 대기 p95 1.60ms, 점유 p95 45.3ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.3, CPU 0.1.
- `peak3x-p2-t30000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 2개. 포장 완료 5.0건/s, 커넥션 획득 대기 p95 15.40ms, 점유 p95 45.8ms, 대기 줄(pending) 최대 1. DB 상위 대기: IdleInTx:app 0.3, CPU 0.1.
- `peak3x-p20-t30000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 20개. 포장 완료 5.0건/s, 커넥션 획득 대기 p95 1.59ms, 점유 p95 45.9ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.4, CPU 0.1.
- `peak3x-p40-t30000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 40개. 포장 완료 5.0건/s, 커넥션 획득 대기 p95 1.57ms, 점유 p95 45.3ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.2, CPU 0.1.
- `peak3x-p5-t30000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 5개. 포장 완료 5.0건/s, 커넥션 획득 대기 p95 1.62ms, 점유 p95 44.8ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.3, CPU 0.1.
