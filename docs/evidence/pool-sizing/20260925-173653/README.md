# 풀 크기 스윕 결과 — 20260925-173653

생성: 2026-09-26 02:30. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-173653", "pool_sizes": "40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "probe50:50:0:0:0 probe100:100:0:0:0", "repeat": 1, "warmup_s": 15, "measure_s": 45, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "3cc3651"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| probe100 | 40 | 30000 | 200 | 1 | 131.8 | 346.62 / 146.73 | 543.5 / 97.3 | 1282.6 | 1285 / 3169 | 429 | 61 | 40 | 101 | 45% | 71% | 39.0 | Lock:tuple 24.5, IdleInTx:app 10.1, Lock:transactionid 2.6 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790325889000&to=1790325993000) |
| probe50 | 40 | 30000 | 200 | 1 | 135.8 | 56.94 / 24.21 | 504.4 / 99.7 | 1081.1 | 1064 / 3588 | 96 | 11 | 40 | 51 | 47% | 76% | 39.0 | Lock:tuple 24.2, IdleInTx:app 10.6, Lock:transactionid 2.6 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790325601000&to=1790325705000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **probe100** (timeout 30000ms, threads 200): 최고 TPS 131.8(pool 40). 규칙1(최고 TPS 98% 이상 최소 풀) = 40, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 40 71%
- **probe50** (timeout 30000ms, threads 200): 최고 TPS 135.8(pool 40). 규칙1(최고 TPS 98% 이상 최소 풀) = 40, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 40 69%

## 캡션 초안

- `probe100-p40-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 40개. 포장 완료 131.8건/s, 커넥션 획득 대기 p95 346.62ms, 점유 p95 543.5ms, 대기 줄(pending) 최대 61. DB 상위 대기: Lock:tuple 24.5, IdleInTx:app 10.1.
- `probe50-p40-t30000-th200-r1`: 작업자 50명(사이클 0ms), 풀 40개. 포장 완료 135.8건/s, 커넥션 획득 대기 p95 56.94ms, 점유 p95 504.4ms, 대기 줄(pending) 최대 11. DB 상위 대기: Lock:tuple 24.2, IdleInTx:app 10.6.
