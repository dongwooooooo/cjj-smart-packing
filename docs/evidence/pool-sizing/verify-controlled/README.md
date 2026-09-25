# 풀 크기 스윕 결과 — verify-controlled

생성: 2026-09-26 00:45. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260926-000944", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "39f09c2"}
{"started": "20260926-001748", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "39f09c2"}
{"started": "20260926-002540", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "39f09c2"}
{"started": "20260926-003330", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "39f09c2"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 3000 | 200 | 1 | 120.4 | 397.25 / 248.66 | 65.7 / 27.1 | 463.0 | 464 / 2300 | 429 | 91 | 10 | 101 | 39% | 28% | 9.4 | IdleInTx:app 7.2, Lock:transactionid 0.9, CPU 0.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790349208000&to=1790349448000) |
| sat | 10 | 3000 | 200 | 2 | 124.9 | 374.73 / 239.20 | 63.6 / 26.0 | 443.5 | 442 / 1033 | 410 | 91 | 10 | 101 | 44% | 29% | 9.5 | IdleInTx:app 7.1, Lock:transactionid 1.0, CPU 0.7 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790350630000&to=1790350870000) |
| sat | 10 | 30000 | 200 | 1 | 125.4 | 374.20 / 238.02 | 62.9 / 25.9 | 441.0 | 442 / 1035 | 405 | 91 | 10 | 101 | 52% | 29% | 9.5 | IdleInTx:app 6.9, Lock:transactionid 1.0, CPU 0.6 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790349690000&to=1790349930000) |
| sat | 10 | 30000 | 200 | 2 | 122.7 | 382.44 / 244.15 | 65.0 / 26.6 | 448.4 | 448 / 1825 | 413 | 91 | 10 | 101 | 41% | 27% | 9.4 | IdleInTx:app 7.3, Lock:transactionid 0.9, CPU 0.5 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790350159000&to=1790350399000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 3000ms, threads 200): 최고 TPS 122.6(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 17%
- **sat** (timeout 30000ms, threads 200): 최고 TPS 124.0(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 18%

## 캡션 초안

- `sat-p10-t3000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 120.4건/s, 커넥션 획득 대기 p95 397.25ms, 점유 p95 65.7ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.2, Lock:transactionid 0.9.
- `sat-p10-t3000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 124.9건/s, 커넥션 획득 대기 p95 374.73ms, 점유 p95 63.6ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.1, Lock:transactionid 1.0.
- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 125.4건/s, 커넥션 획득 대기 p95 374.20ms, 점유 p95 62.9ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 6.9, Lock:transactionid 1.0.
- `sat-p10-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 122.7건/s, 커넥션 획득 대기 p95 382.44ms, 점유 p95 65.0ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.3, Lock:transactionid 0.9.
