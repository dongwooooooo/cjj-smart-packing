# 풀 크기 스윕 결과 — 

생성: 2026-09-26 13:31. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260926-130432", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "72d3480"}
{"started": "20260926-131120", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "72d3480"}
{"started": "20260926-131757", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "72d3480"}
{"started": "20260926-132438", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "72d3480"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 3000 | 200 | 1 | 117.3 | 442.91 / 254.86 | 65.1 / 27.8 | 511.5 | 512 / 3481 | 468 | 91 | 10 | 101 | 57% | 35% | 9.5 | IdleInTx:app 6.7, Lock:transactionid 0.9, Client:ClientRead 0.7 | 0.03% | 16 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790396025000&to=1790396265000) |
| sat | 10 | 3000 | 200 | 2 | 118.0 | 434.58 / 253.78 | 64.4 / 27.6 | 498.6 | 499 / 3092 | 467 | 91 | 10 | 101 | 54% | 31% | 9.4 | IdleInTx:app 6.7, Lock:transactionid 0.9, Client:ClientRead 0.7 | 0.00% | 3 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790396426000&to=1790396666000) |
| sat | 10 | 3000 | 200 | 1 | 84.9 | 963.08 / 350.63 | 83.5 / 38.5 | 1106.6 | 1091 / 6643 | 1050 | 91 | 10 | 101 | 67% | 26% | 9.4 | IdleInTx:app 6.2, CPU 1.2, Client:ClientRead 0.8 | 0.24% | 115 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790395620000&to=1790395860000) |
| sat | 10 | 3000 | 200 | 2 | 42.9 | 2938.09 / 612.84 | 134.0 / 76.8 | 2653.8 | 2451 / 17152 | 3002 | 91 | 10 | 101 | 62% | 18% | 9.1 | IdleInTx:app 4.1, CPU 3.0, Lock:transactionid 0.8 | 5.55% | 1453 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790396838000&to=1790397078000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 3000ms, threads 200): 최고 TPS 90.8(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 15%

## 캡션 초안

- `sat-after-p10-t3000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 117.3건/s, 커넥션 획득 대기 p95 442.91ms, 점유 p95 65.1ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 6.7, Lock:transactionid 0.9.
- `sat-after-p10-t3000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 118.0건/s, 커넥션 획득 대기 p95 434.58ms, 점유 p95 64.4ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 6.7, Lock:transactionid 0.9.
- `sat-before-p10-t3000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 84.9건/s, 커넥션 획득 대기 p95 963.08ms, 점유 p95 83.5ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 6.2, CPU 1.2.
- `sat-before-p10-t3000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 42.9건/s, 커넥션 획득 대기 p95 2938.09ms, 점유 p95 134.0ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 4.1, CPU 3.0.
