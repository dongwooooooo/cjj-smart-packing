# 풀 크기 스윕 결과 — sat

생성: 2026-09-25 23:08. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-202417", "pool_sizes": "2", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-203054", "pool_sizes": "5", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-203723", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-204351", "pool_sizes": "20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-205019", "pool_sizes": "40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-205818", "pool_sizes": "40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-210507", "pool_sizes": "20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-211140", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-211816", "pool_sizes": "5", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-212447", "pool_sizes": "2", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-213958", "pool_sizes": "30", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 30000 | 200 | 1 | 113.4 | 428.60 / 264.01 | 68.9 / 28.7 | 491.4 | 491 / 1285 | 452 | 91 | 10 | 101 | 62% | 26% | 9.5 | IdleInTx:app 7.0, Lock:transactionid 0.9, CPU 0.9 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790336380000&to=1790336620000) |
| sat | 10 | 30000 | 200 | 2 | 106.7 | 466.65 / 280.40 | 75.1 / 30.5 | 542.0 | 546 / 1775 | 493 | 91 | 10 | 101 | 70% | 26% | 9.5 | IdleInTx:app 7.0, CPU 0.8, Lock:transactionid 0.8 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790338442000&to=1790338682000) |
| sat | 2 | 30000 | 200 | 1 | 29.3 | 1808.87 / 1104.84 | 39.6 / 21.9 | 1827.2 | 1839 / 4176 | 1832 | 99 | 2 | 101 | 30% | 14% | 1.9 | IdleInTx:app 1.5, CPU 0.3, IO:WalSync 0.0 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790335599000&to=1790335839000) |
| sat | 2 | 30000 | 200 | 2 | 25.4 | 2390.33 / 1294.74 | 42.1 / 25.7 | 2418.4 | 2371 / 3732 | 2356 | 99 | 2 | 101 | 44% | 13% | 1.9 | IdleInTx:app 1.4, CPU 0.5, IO:WalSync 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790339226000&to=1790339466000) |
| sat | 20 | 30000 | 200 | 1 | 122.0 | 392.38 / 218.62 | 204.5 / 53.8 | 647.1 | 647 / 2025 | 422 | 81 | 20 | 101 | 72% | 31% | 19.8 | IdleInTx:app 9.2, Lock:tuple 6.1, Lock:transactionid 2.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790336769000&to=1790337009000) |
| sat | 20 | 30000 | 200 | 2 | 119.3 | 405.47 / 223.00 | 208.8 / 55.0 | 639.7 | 644 / 2018 | 433 | 81 | 20 | 101 | 72% | 30% | 19.4 | IdleInTx:app 8.9, Lock:tuple 6.0, Lock:transactionid 2.3 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790338049000&to=1790338289000) |
| sat | 30 | 30000 | 200 | 1 | 56.7 | 1420.85 / 413.84 | 783.9 / 176.2 | 3379.1 | 3368 / 12667 | 1428 | 71 | 30 | 101 | 75% | 19% | 38.3 | Lock:tuple 24.5, IdleInTx:app 6.1, CPU 3.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790340139000&to=1790340379000) |
| sat | 40 | 30000 | 200 | 1 | 39.3 | 1613.98 / 502.93 | 2001.3 / 327.8 | 6323.0 | 6336 / 14556 | 1672 | 61 | 40 | 101 | 72% | 16% | 41.6 | Lock:tuple 33.2, IdleInTx:app 3.4, CPU 2.2 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790337163000&to=1790337403000) |
| sat | 40 | 30000 | 200 | 2 | 45.2 | 1394.54 / 436.36 | 1536.7 / 287.3 | 5211.5 | 5298 / 24541 | 1445 | 61 | 40 | 101 | 75% | 16% | 42.6 | Lock:tuple 32.6, IdleInTx:app 4.3, CPU 2.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790337643000&to=1790337883000) |
| sat | 5 | 30000 | 200 | 1 | 71.0 | 640.64 / 446.10 | 46.4 / 22.9 | 703.5 | 687 / 1560 | 652 | 96 | 5 | 101 | 50% | 20% | 4.6 | IdleInTx:app 3.7, CPU 0.5, IO:WalSync 0.2 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790335992000&to=1790336232000) |
| sat | 5 | 30000 | 200 | 2 | 67.1 | 736.13 / 473.33 | 47.4 / 24.3 | 788.5 | 782 / 1709 | 769 | 96 | 5 | 101 | 53% | 19% | 4.7 | IdleInTx:app 3.7, CPU 0.7, IO:WalSync 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790338834000&to=1790339074000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 30000ms, threads 200): 최고 TPS 120.7(pool 20). 규칙1(최고 TPS 98% 이상 최소 풀) = 20, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = 10. DB 대기 비중: pool 2 4%, pool 5 7%, pool 10 16%, pool 20 45%, pool 30 72%, pool 40 83%

## 캡션 초안

- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 113.4건/s, 커넥션 획득 대기 p95 428.60ms, 점유 p95 68.9ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.0, Lock:transactionid 0.9.
- `sat-p10-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 106.7건/s, 커넥션 획득 대기 p95 466.65ms, 점유 p95 75.1ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.0, CPU 0.8.
- `sat-p2-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 2개. 포장 완료 29.3건/s, 커넥션 획득 대기 p95 1808.87ms, 점유 p95 39.6ms, 대기 줄(pending) 최대 99. DB 상위 대기: IdleInTx:app 1.5, CPU 0.3.
- `sat-p2-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 2개. 포장 완료 25.4건/s, 커넥션 획득 대기 p95 2390.33ms, 점유 p95 42.1ms, 대기 줄(pending) 최대 99. DB 상위 대기: IdleInTx:app 1.4, CPU 0.5.
- `sat-p20-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 122.0건/s, 커넥션 획득 대기 p95 392.38ms, 점유 p95 204.5ms, 대기 줄(pending) 최대 81. DB 상위 대기: IdleInTx:app 9.2, Lock:tuple 6.1.
- `sat-p20-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 119.3건/s, 커넥션 획득 대기 p95 405.47ms, 점유 p95 208.8ms, 대기 줄(pending) 최대 81. DB 상위 대기: IdleInTx:app 8.9, Lock:tuple 6.0.
- `sat-p30-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 30개. 포장 완료 56.7건/s, 커넥션 획득 대기 p95 1420.85ms, 점유 p95 783.9ms, 대기 줄(pending) 최대 71. DB 상위 대기: Lock:tuple 24.5, IdleInTx:app 6.1.
- `sat-p40-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 40개. 포장 완료 39.3건/s, 커넥션 획득 대기 p95 1613.98ms, 점유 p95 2001.3ms, 대기 줄(pending) 최대 61. DB 상위 대기: Lock:tuple 33.2, IdleInTx:app 3.4.
- `sat-p40-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 40개. 포장 완료 45.2건/s, 커넥션 획득 대기 p95 1394.54ms, 점유 p95 1536.7ms, 대기 줄(pending) 최대 61. DB 상위 대기: Lock:tuple 32.6, IdleInTx:app 4.3.
- `sat-p5-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 5개. 포장 완료 71.0건/s, 커넥션 획득 대기 p95 640.64ms, 점유 p95 46.4ms, 대기 줄(pending) 최대 96. DB 상위 대기: IdleInTx:app 3.7, CPU 0.5.
- `sat-p5-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 5개. 포장 완료 67.1건/s, 커넥션 획득 대기 p95 736.13ms, 점유 p95 47.4ms, 대기 줄(pending) 최대 96. DB 상위 대기: IdleInTx:app 3.7, CPU 0.7.
