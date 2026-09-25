# 풀 크기 스윕 결과 — sat

생성: 2026-09-25 20:23. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-195053", "pool_sizes": "2", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-195725", "pool_sizes": "5", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-200355", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-201027", "pool_sizes": "20", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
{"started": "20260925-201659", "pool_sizes": "40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "500e2b9"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 30000 | 200 | 1 | 95.3 | 385.85 / 242.84 | 63.9 / 26.8 | 445.8 | 451 / 1388 | 413 | 91 | 10 | 101 | 60% | 22% | 7.4 | IdleInTx:app 5.6, Lock:transactionid 0.7, CPU 0.5 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790334374000&to=1790334614000) |
| sat | 2 | 30000 | 200 | 1 | 31.4 | 1401.07 / 1039.72 | 39.1 / 20.6 | 1412.7 | 1362 / 3099 | 1367 | 99 | 2 | 101 | 31% | 14% | 1.9 | IdleInTx:app 1.6, CPU 0.2, IO:WalSync 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790333590000&to=1790333830000) |
| sat | 20 | 30000 | 200 | 1 | 71.6 | 358.85 / 191.57 | 184.6 / 48.6 | 555.5 | 556 / 1693 | 389 | 81 | 20 | 101 | 62% | 22% | 11.7 | IdleInTx:app 5.6, Lock:tuple 3.5, Lock:transactionid 1.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790334766000&to=1790335006000) |
| sat | 40 | 30000 | 200 | 1 | 96.0 | 467.53 / 206.75 | 721.7 / 137.7 | 1973.6 | 1981 / 10243 | 506 | 62 | 40 | 101 | 73% | 25% | 40.3 | Lock:tuple 27.1, IdleInTx:app 7.7, Lock:transactionid 2.5 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790335159000&to=1790335399000) |
| sat | 5 | 30000 | 200 | 1 | 75.5 | 610.73 / 419.12 | 44.0 / 21.5 | 656.0 | 644 / 1262 | 623 | 96 | 5 | 101 | 44% | 20% | 4.7 | IdleInTx:app 4.0, CPU 0.4, Lock:transactionid 0.2 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790333984000&to=1790334224000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 30000ms, threads 200): 최고 TPS 96.0(pool 40). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = 10. DB 대기 비중: pool 2 5%, pool 5 7%, pool 10 17%, pool 20 43%, pool 40 74%

## 캡션 초안

- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 95.3건/s, 커넥션 획득 대기 p95 385.85ms, 점유 p95 63.9ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 5.6, Lock:transactionid 0.7.
- `sat-p2-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 2개. 포장 완료 31.4건/s, 커넥션 획득 대기 p95 1401.07ms, 점유 p95 39.1ms, 대기 줄(pending) 최대 99. DB 상위 대기: IdleInTx:app 1.6, CPU 0.2.
- `sat-p20-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 71.6건/s, 커넥션 획득 대기 p95 358.85ms, 점유 p95 184.6ms, 대기 줄(pending) 최대 81. DB 상위 대기: IdleInTx:app 5.6, Lock:tuple 3.5.
- `sat-p40-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 40개. 포장 완료 96.0건/s, 커넥션 획득 대기 p95 467.53ms, 점유 p95 721.7ms, 대기 줄(pending) 최대 62. DB 상위 대기: Lock:tuple 27.1, IdleInTx:app 7.7.
- `sat-p5-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 5개. 포장 완료 75.5건/s, 커넥션 획득 대기 p95 610.73ms, 점유 p95 44.0ms, 대기 줄(pending) 최대 96. DB 상위 대기: IdleInTx:app 4.0, CPU 0.4.
