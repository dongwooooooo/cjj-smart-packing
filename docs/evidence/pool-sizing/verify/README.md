# 풀 크기 스윕 결과 — verify

생성: 2026-09-25 23:08. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-222257", "pool_sizes": "10", "conn_timeouts_ms": "1000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
{"started": "20260925-222929", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
{"started": "20260925-223605", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
{"started": "20260925-224242", "pool_sizes": "10", "conn_timeouts_ms": "1000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 180, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 1000 | 200 | 1 | 106.1 | 454.18 / 281.97 | 73.5 / 30.7 | 523.3 | 529 / 1151 | 481 | 91 | 10 | 101 | 72% | 25% | 9.5 | IdleInTx:app 6.9, CPU 0.8, Lock:transactionid 0.8 | 0.03% | 5 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790342714000&to=1790342954000) |
| sat | 10 | 1000 | 200 | 2 | 84.1 | 793.80 / 332.87 | 86.4 / 37.8 | 936.7 | 939 / 2968 | 855 | 91 | 10 | 101 | 74% | 25% | 9.8 | IdleInTx:app 6.3, CPU 1.3, Client:ClientRead 0.9 | 2.76% | 1059 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790343909000&to=1790344149000) |
| sat | 10 | 30000 | 200 | 1 | 103.5 | 499.50 / 291.62 | 77.5 / 31.7 | 571.9 | 561 / 1595 | 516 | 91 | 10 | 101 | 73% | 26% | 10.3 | IdleInTx:app 7.4, CPU 0.9, Client:ClientRead 0.8 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790343111000&to=1790343351000) |
| sat | 10 | 30000 | 200 | 2 | 95.1 | 612.41 / 315.80 | 81.6 / 34.4 | 738.5 | 748 / 1958 | 647 | 91 | 10 | 101 | 73% | 25% | 9.5 | IdleInTx:app 6.6, CPU 1.0, Client:ClientRead 0.8 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790343509000&to=1790343749000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 1000ms, threads 200): 최고 TPS 95.1(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 13%
- **sat** (timeout 30000ms, threads 200): 최고 TPS 99.3(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 12%

## 캡션 초안

- `sat-p10-t1000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 106.1건/s, 커넥션 획득 대기 p95 454.18ms, 점유 p95 73.5ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 6.9, CPU 0.8.
- `sat-p10-t1000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 84.1건/s, 커넥션 획득 대기 p95 793.80ms, 점유 p95 86.4ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 6.3, CPU 1.3.
- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 103.5건/s, 커넥션 획득 대기 p95 499.50ms, 점유 p95 77.5ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.4, CPU 0.9.
- `sat-p10-t30000-th200-r2`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 95.1건/s, 커넥션 획득 대기 p95 612.41ms, 점유 p95 81.6ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 6.6, CPU 1.0.
