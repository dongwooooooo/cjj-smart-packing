# 원장 커서 재측정 — 수정 전 대조기, 정착 창 전제 준수·위반, IT 로그, 동시 진행 건수 (2026-09-25)

글 F(`docs/blog/drafts/f-ledger-cursor.md`)의 근거 재측정이다. 모두 로컬에서 실행했다. 원격 환경(EC2, 부하 발생기, RDS, Prometheus, Grafana)에는 접속하지 않았다.

## 측정 환경

| 항목 | 값 |
| --- | --- |
| DB | 로컬 docker `postgres:18.6` 임시 컨테이너(`ledger-cursor-pg`, 포트 비공개, 실행 후 삭제). `PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on aarch64`, `timezone = Etc/UTC` |
| 클라이언트 | 컨테이너 안 psql, `--echo-queries`(서버로 보낸 문장을 그대로 출력) |
| 코드 기준 | backend main `f87a37e`. 수정 전 집계기 SQL은 `4a63045~1`의 `StockBalanceCollector.ADVANCE`, 수정 전 대조기 SQL은 `83dcf67`의 `StockReconciler.MISMATCHES`·`REBUILD`를 그대로 옮겼다(`git show <커밋>:<경로>`로 확인) |
| IT | Gradle 9.7.1, Testcontainers `postgres:18.6` |

세션 동시 실행은 `scripts/run.sh`가 맡는다. setup.sql을 실행한 뒤 DB 시각 기준 2초 뒤를 공통 기준 시각 `t0`로 정하고, `session_*.sql`을 동시에 띄운다. 각 세션은 `pg_sleep_until(:'t0' + interval 'N s')`로 자기 시점을 맞춘다. 세션 A의 락 대기는 실제 박스 행 락이 아니라 `pg_sleep(4)`로 흉내 낸 것이다.

```
./scripts/run.sh scripts/r1 logs/r1-prefix-collector-reconciler.log
./scripts/run.sh scripts/r2 logs/r2-settle5-wait4.log -v settle=5
./scripts/run.sh scripts/r2 logs/r2-settle3-wait4-control.log -v settle=3
```

두 시나리오 모두 원장 3행(입고 +100, 조정 −1, −6)을 넣고 스냅샷을 `(qty 93, last_tx_id 3)`으로 둔 상태에서 시작한다. 원장 진실(`ledger_truth`)은 원장 전체 합이고, 조회값(`on_hand_read`)은 `v_stock_on_hand`와 같은 식(스냅샷 + `id > last_tx_id`인 원장 합)이다.

## R1. 수정 전 집계기 + 수정 전 대조기

로그: `logs/r1-prefix-collector-reconciler.log` (실행 2026-09-25T07:12:10Z). 세션 A는 늦게 커밋하는 포장 완료 3건(A1~A3), 세션 B는 바로 커밋하는 포장 완료 3건(B1~B3), 세션 K는 집계기·대조기 역할이다.

| 시각(UTC) | 세션 | 사건 | 스냅샷 (qty, last) | 조회값 / 원장 진실 |
| --- | --- | --- | --- | --- |
| 07:12:12.695 | A | A1 INSERT → id 4 (−1), `pg_sleep(4)` | (93, 3) | |
| 07:12:13.198 | B | B1 INSERT → id 5 (−2), 즉시 커밋 | | |
| 07:12:13.398 | K | 집계 1회차. 보이는 미집계 행 id 5뿐, `UPDATE 1` | (91, 5) | 91 / 91 |
| 07:12:16.705 | A | A1 커밋 | | |
| 07:12:17.198 | K | 집계 2회차. 미집계 행 0 rows, `UPDATE 0` | (91, 5) | **91 / 90** |
| 07:12:17.698 | K | 대조 1회차(미커밋 행 없음). MISMATCHES 1행 `derived 91, ledger_total 90` → REBUILD `UPDATE 1` → MISMATCHES 0 rows | (90, 5) | 90 / 90 |
| 07:12:18.700 | A | A2 INSERT → id 6 (−3), `pg_sleep(4)` | | |
| 07:12:19.203 | B | B2 INSERT → id 7 (−4), 즉시 커밋 | | |
| 07:12:19.696 | K | 집계 3회차. 보이는 미집계 행 id 7뿐, `UPDATE 1` | (86, 7) | 86 / 86 |
| 07:12:22.710 | A | A2 커밋 | | |
| 07:12:22.898 | K | 조회 | (86, 7) | **86 / 83** |
| 07:12:23.199 | A | A3 INSERT → id 8 (−5), `pg_sleep(4)` | | |
| 07:12:23.695 | B | B3 INSERT → id 9 (−3), 즉시 커밋 | | |
| 07:12:23.899 | K | 대조 2회차(A3 미커밋). MISMATCHES 1행 `derived 83, ledger_total 80` → REBUILD `UPDATE 1` | (80, 9) | 80 / 80 |
| 07:12:27.210 | A | A3 커밋 | | |
| 07:12:27.702 | K | 조회 → 집계 4회차 `UPDATE 0` → MISMATCHES 1행 `derived 80, ledger_total 75` | (80, 9) | **80 / 75** |
| 07:12:28.197 | K | 대조 3회차(미커밋 행 없음). REBUILD `UPDATE 1` → MISMATCHES 0 rows | (75, 9) | 75 / 75 |

판독:

- 수정 전 집계기 단독으로는 누락이 복구되지 않는다. 집계 2회차와 4회차가 모두 `UPDATE 0`이다.
- 수정 전 대조기는 미커밋 원장 행이 없을 때 누락을 복구한다(대조 1회차, 3회차). REBUILD가 `qty = 원장 전체 합`, `last_tx_id = MAX(id) 전체`로 스냅샷을 다시 쓰기 때문이다.
- REBUILD 자체도 같은 커서 규칙(보이는 행의 `MAX(id)`)이라, 실행 순간에 더 작은 id의 미커밋 행이 있으면 그 행을 건너뛴다(대조 2회차가 id 8을 건너뛰고 last를 9로 옮김). 누락과 복구가 반복될 수 있다.
- 따라서 "영구 누락"은 집계기만 볼 때 성립한다. 대조기를 포함하면 "다음 대조(주기 60초, `inventory.reconciler.interval-ms` 기본값)까지 조회값이 틀리고, 대조 시점에 역전된 미커밋 행이 있으면 다시 틀린다"가 맞다.
- 지표 `inventory.reconcile.mismatch`는 `83dcf67` 코드에서 `mismatch.set(rows.size())`, 즉 MISMATCHES 결과 행 수다. 이 실행에서 MISMATCHES 행 수는 대조 1회차 전 1 → 후 0, 집계 4회차 뒤 1 → 대조 3회차 후 0이었다. 앱을 띄워 게이지 값을 직접 읽지는 않았다.
- 최종 판별 쿼리: `snapshot_qty 75, last_tx_id 9, ledger_sum_upto_cursor 75`(복구 후라 일치).

## R2. 수정 후 집계기 — 정착 창 5초(전제 준수)와 3초(전제 위반)

세션 A는 원장 행을 넣고 4초 뒤 커밋한다. 정착 창 W가 5초면 "원장 쓰기 트랜잭션은 행을 넣은 뒤 W초 안에 끝난다"는 전제를 지키고, 3초면 어긴다. 두 실행은 같은 스크립트이고 `-v settle=` 값만 다르다. 집계기 SQL은 `f87a37e` `StockBalanceCollector.ADVANCE`이며 `?::float8` 두 개를 `:settle::float8`로 바꿨다(로그에는 치환된 값이 찍힌다). `age_s`는 `statement_timestamp() − created_at`이다.

### 창 5초, A 대기 4초 — `logs/r2-settle5-wait4.log` (실행 2026-09-25T07:12:28Z)

| 시각(UTC) | 세션 | 사건 | 보이는 미집계 행 (id: age_s) | 결과 | 스냅샷 | 조회값 / 원장 진실 |
| --- | --- | --- | --- | --- | --- | --- |
| 07:12:30.503 | A | INSERT → id 4 (−1), `pg_sleep(4)` | | | (93, 3) | |
| 07:12:31.005 | B | INSERT → id 5 (−2), 즉시 커밋 | | | | |
| 07:12:31.201 | K | 집계 1회차 | 5: 0.194 | `UPDATE 0` | (93, 3) | 91 / 91 |
| 07:12:34.202 | K | 집계 2회차 (A 미커밋) | 5: 3.195 | `UPDATE 0` | (93, 3) | 91 / 91 |
| 07:12:34.510 | A | 커밋 | | | | |
| 07:12:36.500 | K | 집계 3회차 | 4: 5.996, 5: 5.493 | `UPDATE 1` | (90, 5) | 90 / 90 |

최종: `on_hand_read 90, ledger_truth 90`, 판별 쿼리 `snapshot_qty 90, last_tx_id 5, ledger_sum_upto_cursor 90`, `visible_to_reads` id 4 = f, id 5 = f.

### 창 3초, A 대기 4초(대조군) — `logs/r2-settle3-wait4-control.log` (실행 2026-09-25T07:12:36Z)

| 시각(UTC) | 세션 | 사건 | 보이는 미집계 행 (id: age_s) | 결과 | 스냅샷 | 조회값 / 원장 진실 |
| --- | --- | --- | --- | --- | --- | --- |
| 07:12:38.809 | A | INSERT → id 4 (−1), `pg_sleep(4)` | | | (93, 3) | |
| 07:12:39.315 | B | INSERT → id 5 (−2), 즉시 커밋 | | | | |
| 07:12:39.511 | K | 집계 1회차 | 5: 0.195 | `UPDATE 0` | (93, 3) | 91 / 91 |
| 07:12:42.511 | K | 집계 2회차 (A 미커밋) | 5: 3.196 | `UPDATE 1` | (91, 5) | 91 / 91 |
| 07:12:42.820 | A | 커밋 | | | | |
| 07:12:44.814 | K | 집계 3회차 | 0 rows | `UPDATE 0` | (91, 5) | **91 / 90** |

최종: `on_hand_read 91, ledger_truth 90`, 판별 쿼리 `snapshot_qty 91, last_tx_id 5, ledger_sum_upto_cursor 90`, `visible_to_reads` id 4 = f, id 5 = f.

판독:

- 전제를 지키면 A가 열려 있는 동안 집계는 창 안의 id 5를 접지 않는다(집계 2회차 `UPDATE 0`). 그동안 조회값은 커밋된 행 기준으로 정확하다(91 / 91). A 커밋 뒤 창이 지나자 id 4·5가 함께 접혀 90 / 90이 된다.
- 전제를 어기면(A가 창보다 오래 열려 있으면) 수정 후 SQL도 수정 전과 같은 누락을 낸다. id 5가 창을 지난 순간(3.196초) A의 id 4는 아직 보이지 않고, 창 안의 행으로도 잡히지 않아 커서가 5로 이동한다.
- `visible_to_reads = f`는 두 실행 모두 id 4·5에 공통이다. 정상 집계된 행과 누락된 행을 이 열로는 구분할 수 없다. 구분 기준은 `snapshot_qty`와 `ledger_sum_upto_cursor`(커서까지의 원장 합)의 차이다: 정상 90 = 90, 누락 91 ≠ 90.
- 이전 검증(창 3초·A 대기 4초, 스크래치 로그)은 전제를 어긴 조합이었다. 그 실행에서 누락이 나지 않은 것은 집계 시점이 A 커밋 뒤였기 때문이며, 대조군은 집계 시점을 A 커밋 전으로 옮기면 누락이 난다는 것을 보여 준다.

## R3. 통합 테스트

| 로그 | 대상 | 결과 |
| --- | --- | --- |
| `logs/r3-settle-it-window5.log` | `StockBalanceCollectorSettleIT` (창 5초, backend `f87a37e` 그대로) | `tests="1" failures="0"`, `커밋_순서가_뒤바뀐_원장_행도_빠지지_않는다()` 6.07초, `BUILD SUCCESSFUL in 17s` |
| `logs/r3-probe-it-window0.log` | 임시 사본 `StockBalanceCollectorSettleProbeIT` (창 0) | `failures="1"`, `Expecting actual: 2L to be less than: 1L` at `StockBalanceCollectorSettleProbeIT.java:82`, `BUILD FAILED in 14s` |

사본의 변경점은 `logs/r3-probe-diff.txt`에 있다. 클래스 이름과 `inventory.collector.settle-seconds=5` → `0` 두 줄뿐이다. 82행은 `assertThat(duringOpenTx.lastTxId()).isLessThan(slowIdHolder.get())`이다. 느린 트랜잭션이 id 1을 받고 열려 있는 동안 커밋된 id 2까지 커서가 이동했다는 뜻이다. 사본은 실행 뒤 test 트리에서 삭제했다(backend `git status` 변경 없음). 로그의 로컬 경로는 `<repo>/`로, XML의 호스트 이름은 `(생략)`으로 바꿨다.

## R4. 포장 완료 동시 진행 건수 (실행 5 기준)

리틀의 법칙(평균 동시 진행 수 = 도착률 × 평균 체류 시간)으로 계산했다.

| 입력 | 값 | 출처 |
| --- | --- | --- |
| 완료 처리량 | 32.6건/s | `docs/evidence/loadtest/README.md` 실행 5 표 |
| k6 완료 평균 소요 | 44.85ms (p50 35ms, p95 73.31ms, max 998.84ms) | `docs/evidence/loadtest/20260924-160456-packing/k6.log` 580행 `complete_duration` |
| RDS 락 대기 세션 최대 | 2 | 같은 README 실행 5 표, 판독 "남은 락 대기 세션 최대 2는 같은 박스 행을 두고 줄을 선 것" |

32.6 × 0.04485 = 1.46. 실행 5 동안 포장 완료 요청은 평균 약 1.5건이 동시에 진행 중이었다. 이 값은 k6가 잰 요청 전체(네트워크, 조회, 원장 INSERT, 박스 락 대기, 커밋) 기준이다. 누락 조건에 직접 걸리는 "원장 INSERT 후 커밋 전" 구간의 길이와 동시 건수는 재지 않았다(실측 필요 — 포장 완료 트랜잭션의 첫 원장 INSERT 시각과 커밋 시각을 서버에서 기록). max 998.84ms는 시작 직후 30초 동안 HikariCP pending 38이 찍힌 구간을 포함한 값이다.

## R5. RDS 엔진 버전

`infra/variables.tf`의 `rds_engine_version` 기본값은 `"18"`(설명: "PostgreSQL 메이저 버전. 팀 구성은 postgres:18 (D-16).")이고, `infra/terraform.tfvars`에는 이 변수를 덮어쓰는 줄이 없다. `transaction_timeout`은 PostgreSQL 17에서 추가된 설정이라(릴리스 노트 https://www.postgresql.org/docs/release/17.0/ "Add server variable transaction_timeout") 메이저 18에서 쓸 수 있다. 공식 문서(https://www.postgresql.org/docs/18/runtime-config-client.html)상 시간을 넘기면 문장만 취소되는 것이 아니라 세션이 종료되고, `postgresql.conf`에 두면 모든 세션에 적용되므로 권장하지 않는다고 적혀 있다. prepared transaction은 대상이 아니다. RDS에서 실제 동작 중인 마이너 버전과 파라미터 그룹 허용 여부는 확인하지 않았다(실측 필요 — RDS 접속이 다른 실험에 점유된 상태라 미실행).
