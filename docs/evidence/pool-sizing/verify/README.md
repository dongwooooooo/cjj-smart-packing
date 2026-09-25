# 풀 크기 스윕 결과 — verify

생성: 2026-09-26 02:30. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-233633", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "caaae76"}
{"started": "20260925-234318", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "caaae76"}
{"started": "20260925-235008", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "caaae76"}
{"started": "20260925-235658", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "caaae76"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 3000 | 200 | 1 | 82.5 | 934.23 / 366.68 | 86.5 / 39.9 | 1179.7 | 1146 / 3715 | 926 | 91 | 10 | 101 | 74% | 24% | 9.4 | IdleInTx:app 5.7, CPU 1.6, Lock:transactionid 0.7 | 0.26% | 93 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790347139000&to=1790347379000) |
| sat | 10 | 3000 | 200 | 2 | 55.1 | 1835.59 / 502.04 | 111.4 / 56.3 | 2132.2 | 2248 / 8109 | 1996 | 91 | 10 | 101 | 71% | 20% | 9.2 | IdleInTx:app 4.6, CPU 2.6, Client:ClientRead 0.8 | 2.82% | 578 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790348367000&to=1790348607000) |
| sat | 10 | 30000 | 200 | 1 | 77.4 | 1134.64 / 392.30 | 88.9 / 42.8 | 1387.4 | 1360 / 3391 | 1132 | 91 | 10 | 101 | 73% | 24% | 9.5 | IdleInTx:app 5.6, CPU 1.7, Lock:transactionid 0.8 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790347551000&to=1790347791000) |
| sat | 10 | 30000 | 200 | 2 | 66.4 | 1360.19 / 440.01 | 99.1 / 48.4 | 1630.3 | 1675 / 9155 | 1426 | 91 | 10 | 101 | 74% | 21% | 9.4 | IdleInTx:app 4.9, CPU 2.2, Lock:transactionid 0.9 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790347957000&to=1790348197000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 3000ms, threads 200): 최고 TPS 68.8(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 13%
- **sat** (timeout 30000ms, threads 200): 최고 TPS 71.9(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 15%

## 캡션 초안

- `sat-p10-t3000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 82.5건/s, 커넥션 획득 대기 p95 934.23ms, 점유 p95 86.5ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 5.7, CPU 1.6.
- `sat-p10-t3000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 55.1건/s, 커넥션 획득 대기 p95 1835.59ms, 점유 p95 111.4ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 4.6, CPU 2.6.
- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 77.4건/s, 커넥션 획득 대기 p95 1134.64ms, 점유 p95 88.9ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 5.6, CPU 1.7.
- `sat-p10-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 66.4건/s, 커넥션 획득 대기 p95 1360.19ms, 점유 p95 99.1ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 4.9, CPU 2.2.
