# 풀 크기 스윕 결과 — live-console

> **포폴용 화면이다. 판정에 쓰지 않는다.** 원장 약 30행 기준(09-26 데모 리셋 사고 뒤 새 기준선, 컷오프 id 3131672)이라, 판정에 쓴 원장 되돌림 스윕(`sat-fixed/`, 원장 2만 행)과 직접 비교할 수 없다. 규칙 판정·결정값은 기존 결과(README 4·5절)를 유지한다. 판독 60초라 조건당 표본도 짧다.
>
> 녹화: `console.cast`(asciinema v2, `asciinema play console.cast`), `frames/frame-*.txt`·`.png`(10초마다), `frames/final.*`(마지막 화면). 콘솔 도구 `tools/loadtest/sweep/live_console.py`.


생성: 2026-09-26 22:50. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260926-224138", "pool_sizes": "10 20 40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 60, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "85d079a"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 30000 | 200 | 1 | 140.7 | 350.67 / 212.47 | 53.3 / 23.0 | 385.7 | 407 / 1124 | 359 | 91 | 10 | 102 | 39% | 37% | 9.6 | IdleInTx:app 7.7, Lock:transactionid 0.8, CPU 0.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790430155000&to=1790430275000) |
| sat | 20 | 30000 | 200 | 1 | 162.4 | 327.68 / 161.80 | 146.7 / 39.8 | 452.1 | 468 / 1363 | 362 | 80 | 20 | 101 | 27% | 55% | 19.2 | IdleInTx:app 9.8, Lock:tuple 5.8, Lock:transactionid 2.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790430324000&to=1790430444000) |
| sat | 40 | 30000 | 200 | 1 | 159.8 | 258.45 / 124.71 | 480.0 / 82.8 | 1019.6 | 1008 / 2550 | 287 | 60 | 40 | 101 | 26% | 54% | 39.1 | Lock:tuple 24.0, IdleInTx:app 10.4, Lock:transactionid 2.8 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790430493000&to=1790430613000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 30000ms, threads 200): 최고 TPS 162.4(pool 20). 규칙1(최고 TPS 98% 이상 최소 풀) = 20, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = 20. DB 대기 비중: pool 10 15%, pool 20 45%, pool 40 69%

## 캡션 초안

- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 140.7건/s, 커넥션 획득 대기 p95 350.67ms, 점유 p95 53.3ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.7, Lock:transactionid 0.8.
- `sat-p20-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 162.4건/s, 커넥션 획득 대기 p95 327.68ms, 점유 p95 146.7ms, 대기 줄(pending) 최대 80. DB 상위 대기: IdleInTx:app 9.8, Lock:tuple 5.8.
- `sat-p40-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 40개. 포장 완료 159.8건/s, 커넥션 획득 대기 p95 258.45ms, 점유 p95 480.0ms, 대기 줄(pending) 최대 60. DB 상위 대기: Lock:tuple 24.0, IdleInTx:app 10.4.
