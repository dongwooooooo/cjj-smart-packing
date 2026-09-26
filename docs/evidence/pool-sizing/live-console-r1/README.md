# 풀 크기 스윕 결과 — live-console

> **포폴용 화면이다. 판정에 쓰지 않는다.** 원장 약 30행 기준(09-26 데모 리셋 사고 뒤 새 기준선, 컷오프 id 3131672)이라, 판정에 쓴 원장 되돌림 스윕(`sat-fixed/`, 원장 2만 행)과 직접 비교할 수 없다. 규칙 판정·결정값은 기존 결과(README 4·5절)를 유지한다. 판독 60초라 조건당 표본도 짧다.
>
> 1회차: 콘솔의 '단계' 표시가 부하 중에도 '준비' 로 찍혀 다시 녹화했다(`../live-console/`). 지표 값과 결과 행은 유효하다.
>
> 녹화: `console.cast`(asciinema v2, `asciinema play console.cast`), `frames/frame-*.txt`·`.png`(10초마다), `frames/final.*`(마지막 화면). 콘솔 도구 `tools/loadtest/sweep/live_console.py`.


생성: 2026-09-26 22:40. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.

## 실행 조건 (호출별)

```json
{"started": "20260926-223154", "pool_sizes": "10 20 40", "conn_timeouts_ms": "30000", "tomcat_threads": "200", "loads": "sat:100:0:0:0", "repeat": 1, "warmup_s": 30, "measure_s": 60, "scenario": "packing", "client_timeout": "60s", "lock_inject": "", "image": "cd6222eefbf2", "rds_max_connections": "79", "portfolio_sha": "85d079a"}
```

## 조건별 비교표

Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 `pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.

| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | 완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sat | 10 | 30000 | 200 | 1 | 139.4 | 359.00 / 214.24 | 54.8 / 23.2 | 401.1 | 418 / 1001 | 380 | 91 | 10 | 101 | 36% | 41% | 9.3 | IdleInTx:app 7.1, Lock:transactionid 1.0, Lock:tuple 0.4 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790429570000&to=1790429690000) |
| sat | 20 | 30000 | 200 | 1 | 160.2 | 323.33 / 164.34 | 153.0 / 40.5 | 462.1 | 468 / 924 | 358 | 80 | 20 | 101 | 40% | 53% | 19.2 | IdleInTx:app 10.8, Lock:tuple 5.0, Lock:transactionid 2.3 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790429739000&to=1790429859000) |
| sat | 40 | 30000 | 200 | 1 | 155.9 | 256.96 / 127.21 | 472.0 / 84.6 | 1119.5 | 1091 / 3413 | 280 | 60 | 40 | 101 | 24% | 47% | 39.3 | Lock:tuple 24.6, IdleInTx:app 10.2, Lock:transactionid 2.7 | 0.00% | 0 | [보기](http://13.124.19.3:3000/d/cjj-pool-sizing/?orgId=1&from=1790429908000&to=1790430028000) |

## 판정 규칙 기계 적용 (초안, 사람이 확인)

- **sat** (timeout 30000ms, threads 200): 최고 TPS 160.2(pool 20). 규칙1(최고 TPS 98% 이상 최소 풀) = 20, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = None, 규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = 20. DB 대기 비중: pool 10 19%, pool 20 39%, pool 40 70%

## 캡션 초안

- `sat-p10-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 10개. 포장 완료 139.4건/s, 커넥션 획득 대기 p95 359.00ms, 점유 p95 54.8ms, 대기 줄(pending) 최대 91. DB 상위 대기: IdleInTx:app 7.1, Lock:transactionid 1.0.
- `sat-p20-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 20개. 포장 완료 160.2건/s, 커넥션 획득 대기 p95 323.33ms, 점유 p95 153.0ms, 대기 줄(pending) 최대 80. DB 상위 대기: IdleInTx:app 10.8, Lock:tuple 5.0.
- `sat-p40-t30000-th200-r1`: 작업자 100명(사이클 0ms), 풀 40개. 포장 완료 155.9건/s, 커넥션 획득 대기 p95 256.96ms, 점유 p95 472.0ms, 대기 줄(pending) 최대 60. DB 상위 대기: Lock:tuple 24.6, IdleInTx:app 10.2.
