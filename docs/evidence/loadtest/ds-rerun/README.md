# 풀 크기 스윕 결과 — ds-rerun

생성: 2026-09-28 20:56. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260928-203832", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "ds50:50:0:0:1000", "repeat": 1, "warmup_s": 0, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "91180ff"}
{"started": "20260928-204321", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "ds50:50:0:0:1000", "repeat": 1, "warmup_s": 0, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "91180ff"}
{"started": "20260928-204824", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat100:100:0:0:0", "repeat": 1, "warmup_s": 0, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "91180ff"}
{"started": "20260928-205234", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat100:100:0:0:0", "repeat": 1, "warmup_s": 0, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "91180ff"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ds50 | 10 | 30000 | 200 | 1 | 46.3 | 0.10 / 1.43 | 44.9 / 20.7 | 63.5 | 64 / 868 | 34 | 3 | 10 | 14 | 14% | 22% | 2.8 | IdleInTx:app 2.4, IO:WalSync 0.1, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790595809000&to=1790596049000) |
| ds50 | 10 | 30000 | 200 | 1 | 46.3 | 1.52 / 2.77 | 51.2 / 22.6 | 74.6 | 72 / 968 | 35 | 5 | 10 | 15 | 16% | 21% | 3.0 | IdleInTx:app 2.5, CPU 0.2, Lock:transactionid 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790595518000&to=1790595758000) |
| sat100 **무효(묶음 소진)** | 10 | 30000 | 200 | 1 | 75.3 | 455.36 / 222.79 | 59.5 / 24.4 | 517.9 | 519 / 2837 | 496 | 91 | 10 | 101 | 31% | 31% | 5.3 | IdleInTx:app 4.4, Lock:transactionid 0.4, CPU 0.2 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790596358000&to=1790596598000) |
| sat100 **무효(묶음 소진)** | 10 | 30000 | 200 | 1 | 75.3 | 479.70 / 235.84 | 66.1 / 25.8 | 532.0 | 534 / 2352 | 527 | 90 | 10 | 101 | 35% | 32% | 5.6 | IdleInTx:app 4.5, Lock:transactionid 0.5, CPU 0.2 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790596110000&to=1790596350000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **ds50** (timeout 30000ms, threads 200): 최고 TPS 46.3(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = 10, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 9%
- **sat100** (timeout 30000ms, threads 200): 최고 TPS 75.3(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 14%

## 캡션 초안

- `ds50-after-p10-t30000-th200-r1`: 작업자 50명(사이클 0ms), 풀 10개. 포장 완료 46.3건/s, 커넥션 획득 대기 p95 0.10ms, 점유 p95 44.9ms, 대기 줄(pending) 최대 3. DB 상위 대기: IdleInTx:app 2.4, IO:WalSync 0.1.
- `ds50-before-p10-t30000-th200-r1`: 작업자 50명(사이클 0ms), 풀 10개. 포장 완료 46.3건/s, 커넥션 획득 대기 p95 1.52ms, 점유 p95 51.2ms, 대기 줄(pending) 최대 5. DB 상위 대기: IdleInTx:app 2.5, CPU 0.2.
- `sat100-after-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 75.3건/s, 커넥션 획득 대기 p95 455.36ms, 점유 p95 59.5ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 4.4, Lock:transactionid 0.4.
- `sat100-before-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 75.3건/s, 커넥션 획득 대기 p95 479.70ms, 점유 p95 66.1ms, 대기 줄(pending) 최대 90. DB 상위 대기: IdleInTx:app 4.5, Lock:transactionid 0.5.
