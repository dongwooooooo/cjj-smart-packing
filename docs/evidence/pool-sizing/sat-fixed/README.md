# 풀 크기 스윕 결과 — sat-fixed

생성: 2026-09-26 01:24. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260926-004947", "pool_sizes": "5", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "a0322b9"}
{"started": "20260926-005747", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "a0322b9"}
{"started": "20260926-010539", "pool_sizes": "20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "a0322b9"}
{"started": "20260926-011331", "pool_sizes": "30", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "a0322b9"}
{"started": "20260926-012125", "pool_sizes": "40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "a0322b9"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 30000 | 200 | 1 | 125.2 | 373.79 / 239.24 | 63.1 / 26.0 | 445.1 | 441 / 1080 | 397 | 91 | 10 | 101 | 38% | 28% | 9.5 | IdleInTx:app 7.0, Lock:transactionid 1.0, CPU 0.6 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790352088000&to=1790352328000) |
| sat | 20 | 30000 | 200 | 1 | 136.6 | 357.51 / 194.45 | 184.4 / 48.0 | 570.9 | 564 / 1429 | 389 | 81 | 20 | 101 | 45% | 43% | 19.3 | IdleInTx:app 9.3, Lock:tuple 6.2, Lock:transactionid 2.5 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790352560000&to=1790352800000) |
| sat | 30 | 30000 | 200 | 1 | 137.6 | 320.17 / 169.03 | 356.8 / 71.9 | 882.2 | 882 / 2462 | 341 | 71 | 30 | 101 | 50% | 40% | 29.3 | Lock:tuple 15.5, IdleInTx:app 9.3, Lock:transactionid 2.6 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790353033000&to=1790353273000) |
| sat | 5 | 30000 | 200 | 1 | 78.4 | 534.08 / 403.35 | 42.8 / 20.7 | 577.3 | 575 / 1391 | 537 | 96 | 5 | 101 | 26% | 20% | 4.7 | IdleInTx:app 3.9, CPU 0.4, IO:WalSync 0.2 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790351606000&to=1790351846000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 30000ms, threads 200): 최고 TPS 137.6(pool 30). 규칙1(최고 TPS 98% 이상 최소 풀) = 20, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = 10. DB 대기 비중: pool 5 8%, pool 10 19%, pool 20 47%, pool 30 63%

## 캡션 초안

- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 125.2건/s, 커넥션 획득 대기 p95 373.79ms, 점유 p95 63.1ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.0, Lock:transactionid 1.0.
- `sat-p20-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 136.6건/s, 커넥션 획득 대기 p95 357.51ms, 점유 p95 184.4ms, 대기 줄(pending) 최대 81. DB 상위 대기: IdleInTx:app 9.3, Lock:tuple 6.2.
- `sat-p30-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 30개. 포장 완료 137.6건/s, 커넥션 획득 대기 p95 320.17ms, 점유 p95 356.8ms, 대기 줄(pending) 최대 71. DB 상위 대기: Lock:tuple 15.5, IdleInTx:app 9.3.
- `sat-p5-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 5개. 포장 완료 78.4건/s, 커넥션 획득 대기 p95 534.08ms, 점유 p95 42.8ms, 대기 줄(pending) 최대 96. DB 상위 대기: IdleInTx:app 3.9, CPU 0.4.
