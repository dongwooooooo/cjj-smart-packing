# 풀 크기 스윕 결과 — sat

생성: 2026-09-28 23:46. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260928-230316", "pool_sizes": "10 20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 150, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "880aec1"}
{"started": "20260928-231741", "pool_sizes": "10 20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 150, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "880aec1"}
{"started": "20260928-233204", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 150, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "880aec1"}
{"started": "20260928-233924", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 150, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "880aec1"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 30000 | 200 | 1 | 170.5 | 294.37 / 175.44 | 30.3 / 18.9 | 330.7 | 336 / 1175 | 331 | 91 | 10 | 101 | 37% | 38% | 9.2 | IdleInTx:app 7.7, CPU 0.8, IO:WalSync 0.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790605288000&to=1790605498000) |
| sat | 10 | 30000 | 200 | 2 | 168.8 | 303.48 / 176.79 | 30.8 / 19.1 | 340.1 | 346 / 1070 | 342 | 91 | 10 | 101 | 39% | 42% | 9.3 | IdleInTx:app 8.0, CPU 0.6, IO:WalSync 0.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790606151000&to=1790606361000) |
| sat | 20 | 30000 | 200 | 1 | 189.4 | 417.71 / 139.93 | 64.8 / 34.2 | 480.7 | 481 / 1436 | 478 | 81 | 20 | 101 | 48% | 73% | 18.5 | IdleInTx:app 16.5, CPU 0.8, IO:WalSync 0.5 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790605711000&to=1790605921000) |
| sat | 10 | 30000 | 200 | 1 | 145.6 | 341.03 / 205.31 | 54.0 / 22.3 | 378.6 | 385 / 814 | 350 | 91 | 10 | 101 | 32% | 33% | 9.3 | IdleInTx:app 7.2, Lock:transactionid 0.9, CPU 0.5 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790604425000&to=1790604635000) |
| sat | 10 | 30000 | 200 | 2 | 140.9 | 349.78 / 212.19 | 55.6 / 23.0 | 388.5 | 404 / 1864 | 376 | 91 | 10 | 101 | 40% | 32% | 9.4 | IdleInTx:app 7.3, Lock:transactionid 0.9, CPU 0.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790606595000&to=1790606805000) |
| sat | 20 | 30000 | 200 | 1 | 167.0 | 305.73 / 158.05 | 139.0 / 39.0 | 447.1 | 450 / 1472 | 324 | 81 | 20 | 101 | 34% | 44% | 19.2 | IdleInTx:app 10.0, Lock:tuple 5.3, Lock:transactionid 2.6 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790604847000&to=1790605057000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 30000ms, threads 200): 최고 TPS 178.2(pool 20). 규칙1(최고 TPS 98% 이상 최소 풀) = 20, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = 20. DB 대기 비중: pool 10 11%, pool 20 25%

## 캡션 초안

- `sat-after-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 170.5건/s, 커넥션 획득 대기 p95 294.37ms, 점유 p95 30.3ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.7, CPU 0.8.
- `sat-after-p10-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 168.8건/s, 커넥션 획득 대기 p95 303.48ms, 점유 p95 30.8ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 8.0, CPU 0.6.
- `sat-after-p20-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 189.4건/s, 커넥션 획득 대기 p95 417.71ms, 점유 p95 64.8ms, 대기 줄(pending) 최대 81. DB 상위 대기: IdleInTx:app 16.5, CPU 0.8.
- `sat-before-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 145.6건/s, 커넥션 획득 대기 p95 341.03ms, 점유 p95 54.0ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.2, Lock:transactionid 0.9.
- `sat-before-p10-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 140.9건/s, 커넥션 획득 대기 p95 349.78ms, 점유 p95 55.6ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.3, Lock:transactionid 0.9.
- `sat-before-p20-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 167.0건/s, 커넥션 획득 대기 p95 305.73ms, 점유 p95 139.0ms, 대기 줄(pending) 최대 81. DB 상위 대기: IdleInTx:app 10.0, Lock:tuple 5.3.
