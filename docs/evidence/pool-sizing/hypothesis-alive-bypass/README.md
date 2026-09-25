# 풀 크기 스윕 결과 — hypothesis-alive-bypass

생성: 2026-09-26 02:30. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260925-221412", "pool_sizes": "10", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "peak3x:300:60000:50000:0", "repeat": 1, "warmup_s": 30, "measure_s": 240, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "316b6d8"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| peak3x | 10 | 30000 | 200 | 1 | 5.0 | 0.10 / 0.00 | 50.2 / 52.3 | 58.1 | 59 / 279 | 35 | 0 | 3 | 3 | 31% | 6% | 0.8 | CPU 0.5, IdleInTx:app 0.3, Client:ClientRead 0.0 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790342224000&to=1790342524000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **peak3x** (timeout 30000ms, threads 200): 최고 TPS 5.0(pool 10). 규칙1(최고 TPS 98% 이상 최소 풀) = 10, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = 10, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = None. DB 대기 비중: pool 10 1%

## 캡션 초안

- `peak3x-p10-t30000-th200-r1`: 작업자 300명(사이클 60000ms), 풀 10개. 포장 완료 5.0건/s, 커넥션 획득 대기 p95 0.10ms, 점유 p95 50.2ms, 대기 줄(pending) 최대 0. DB 상위 대기: CPU 0.5, IdleInTx:app 0.3.
