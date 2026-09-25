# 풀 크기 스윕 결과 — peak

생성: 2026-09-25 18:24. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-175759", "pool_sizes": "2", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-180637", "pool_sizes": "5", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
{"started": "20260925-181624", "pool_sizes": "2", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak1x:100:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "5694b50"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| peak1x | 2 | 30000 | 200 | 1 | 1.9 | 1.69 / 0.50 | 50.4 / 32.3 | 53.6 | 54 / 128 | 27 | 0 | 2 | 2 | 12% | 4% | 0.2 | IdleInTx:app 0.2, CPU 0.1 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790327952000&to=1790328251000) |
| peak1x | 5 | 30000 | 200 | 1 | 1.9 | 25.83 / 3.21 | 54.2 / 32.6 | 72.5 | 71 / 103 | 63 | 9 | 5 | 15 | 14% | 5% | 0.2 | IdleInTx:app 0.1, CPU 0.1, IO:WalSync 0.0 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790327363000&to=1790327662000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **peak1x** (timeout 30000ms, threads 200): 최고 TPS 1.9(pool 5). 규칙1(최고 TPS 98% 이상 최소 풀) = 2, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 2 0%, pool 5 5%

## 캡션 초안

- `peak1x-p2-t30000-th200-r1`: 작업자 100명(사이클 60000ms), 풀 2개. 포장 완료 1.9건/s, 커넥션 획득 대기 p95 1.69ms, 점유 p95 50.4ms, 대기 줄(pending) 최대 0. DB 상위 대기: IdleInTx:app 0.2, CPU 0.1.
- `peak1x-p5-t30000-th200-r1`: 작업자 100명(사이클 60000ms), 풀 5개. 포장 완료 1.9건/s, 커넥션 획득 대기 p95 25.83ms, 점유 p95 54.2ms, 대기 줄(pending) 최대 9. DB 상위 대기: IdleInTx:app 0.1, CPU 0.1.
