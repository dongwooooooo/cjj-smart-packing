# 풀 크기 스윕 결과 — timeout

생성: 2026-09-25 23:08. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-214713", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "10s", "lock_inject": "60:20", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
{"started": "20260925-215556", "pool_sizes": "10", "conn_timeouts_ms": "3000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "10s", "lock_inject": "60:20", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
{"started": "20260925-220427", "pool_sizes": "10", "conn_timeouts_ms": "1000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "10s", "lock_inject": "60:20", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
{"started": "20260925-225052", "pool_sizes": "10", "conn_timeouts_ms": "1000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "10s", "lock_inject": "60:20", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
{"started": "20260925-225932", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "10s", "lock_inject": "60:20", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| peak3x | 10 | 1000 | 200 | 1 | 4.5 | 1039.14 / 139.42 | 56.3 / 105.9 | 1018.3 | 1003 / 10001 | 1004 | 51 | 10 | 62 | 33% | 6% | 1.6 | Lock:tuple 0.5, CPU 0.5, IdleInTx:app 0.3 | 13.28% | 523 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790341639000&to=1790341939000) |
| peak3x | 10 | 1000 | 200 | 2 | 4.5 | 1040.05 / 143.04 | 116.4 / 123.1 | 1027.1 | 1003 / 10001 | 1004 | 55 | 10 | 65 | 34% | 7% | 1.8 | CPU 0.6, Lock:tuple 0.5, IdleInTx:app 0.4 | 13.46% | 538 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790344430000&to=1790344730000) |
| peak3x | 10 | 3000 | 200 | 1 | 4.6 | 2949.18 / 236.38 | 66.4 / 109.0 | 2955.6 | 3003 / 10001 | 3004 | 65 | 10 | 76 | 29% | 6% | 1.6 | CPU 0.5, Lock:tuple 0.5, Lock:transactionid 0.3 | 6.78% | 249 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790341128000&to=1790341428000) |
| peak3x | 10 | 30000 | 200 | 1 | 4.7 | 2931.91 / 520.55 | 57.3 / 104.6 | 9917.5 | 9917 / 10001 | 6669 | 174 | 10 | 184 | 31% | 6% | 1.6 | Lock:tuple 0.5, CPU 0.4, Lock:transactionid 0.3 | 2.63% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790340608000&to=1790340908000) |
| peak3x | 10 | 30000 | 200 | 2 | 4.7 | 3372.34 / 522.99 | 88.9 / 113.5 | 8117.5 | 8141 / 10001 | 6808 | 190 | 10 | 200 | 34% | 6% | 1.8 | CPU 0.6, Lock:tuple 0.4, IdleInTx:app 0.4 | 2.63% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790344950000&to=1790345250000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **peak3x** (timeout 1000ms, threads 200): 최고 TPS 4.5(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 48%
- **peak3x** (timeout 3000ms, threads 200): 최고 TPS 4.6(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 50%
- **peak3x** (timeout 30000ms, threads 200): 최고 TPS 4.7(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 48%

## 캡션 초안

- `peak3x-p10-t1000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 10개. 포장 완료 4.5건/s, 커넥션 획득 대기 p95 1039.14ms, 점유 p95 56.3ms, 대기 줄(pending) 최대 51. DB 상위 대기: Lock:tuple 0.5, CPU 0.5.
- `peak3x-p10-t1000-th200-r2`: 작업자 300명(사이클 60000ms), 풀 10개. 포장 완료 4.5건/s, 커넥션 획득 대기 p95 1040.05ms, 점유 p95 116.4ms, 대기 줄(pending) 최대 55. DB 상위 대기: CPU 0.6, Lock:tuple 0.5.
- `peak3x-p10-t3000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 10개. 포장 완료 4.6건/s, 커넥션 획득 대기 p95 2949.18ms, 점유 p95 66.4ms, 대기 줄(pending) 최대 65. DB 상위 대기: CPU 0.5, Lock:tuple 0.5.
- `peak3x-p10-t30000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 10개. 포장 완료 4.7건/s, 커넥션 획득 대기 p95 2931.91ms, 점유 p95 57.3ms, 대기 줄(pending) 최대 174. DB 상위 대기: Lock:tuple 0.5, CPU 0.4.
- `peak3x-p10-t30000-th200-r2`: 작업자 300명(사이클 60000ms), 풀 10개. 포장 완료 4.7건/s, 커넥션 획득 대기 p95 3372.34ms, 점유 p95 88.9ms, 대기 줄(pending) 최대 190. DB 상위 대기: CPU 0.6, Lock:tuple 0.4.
