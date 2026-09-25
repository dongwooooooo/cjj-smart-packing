# 집계 커서가 놓친 한 줄 — id 순서와 커밋 순서가 다를 때

재고를 원장 방식으로 바꾼 뒤, 머지 전 코드 검토에서 집계 커서의 결함이 나왔다. id를 먼저 받고 늦게 커밋한 원장 행을 커서가 건너뛰어, 조회값이 실제보다 많게 나온다. 행을 넣은 뒤 일정 시간이 지난 원장 행만 집계하는 정착 윈도우(settle window)를 두어 고쳤다.

## 재고 숫자를 쓰는 곳

이 시스템은 풀필먼트 창고의 검수·포장 판단을 맡는다. 재고 숫자를 읽는 경로는 세 곳이다.

1. 출고지시 접수 배치(`POST /api/v1/admin/orders/import`)가 주문마다 가용 재고를 읽어 접수할지 거절할지 정한다.
2. 입고 스캔 응답(`POST /api/v1/inbound/scans`의 `ProductSummary`)이 재고 수량을 담는다.
3. 관리자 재고 조정 API(`POST /api/v1/admin/inventory/adjustments`)가 조정 후 수량을 응답한다.

사업에 직접 닿는 것은 첫째다. 접수 배치의 `OrderScreener`는 요청 수량이 가용 재고보다 많으면 주문을 `INSUFFICIENT_STOCK`으로 거절한다. 가용 재고가 실제보다 많으면 없는 재고에 주문을 받고, 적으면 있는 재고에 주문을 거절한다.

## 원장 재고로 바꾼 이유와 전제

2026-09-22 원장 전환 전 포장 부하 테스트에서 포장 완료가 데드락으로 실패했다. 포장 완료 트랜잭션은 상품 행을 `SELECT FOR UPDATE`로 잠갔는데, 잠그는 순서가 배송단위(주문을 박스 하나 단위로 나눈 출고 단위)마다 달랐다. 작업자 50명이 동시에 포장 완료를 보내자 요청의 40.4%가 500으로 끝났다. p95는 10.07초, 데드락은 356건이었다.

같은 날 출고지시 접수 테스트에서는 가용 재고가 틀렸다. 테스트 전 넣은 재고 +100,000이 원장(`inventory_tx`)에만 기록되고 잔고 컬럼(`product.stock_qty`)은 약 120에 머물렀다. 149주문을 받은 뒤 나머지 주문이 모두 `INSUFFICIENT_STOCK`으로 거절됐다. 두 사건 모두 재고 숫자가 원장과 잔고 컬럼 두 곳에 있고, 잔고 갱신이 트랜잭션 안의 행 락에 묶여 있어서 생겼다.

그래서 원장을 유일한 기준으로 두고, 잔고는 5초마다 원장을 집계한 스냅샷(`stock_balance`)으로 바꿨다. 포장 완료는 상품 행을 잠그지 않고 원장에 차감 행만 넣는다. 조회는 스냅샷에 아직 집계하지 않은 원장 행을 더해 답한다. 이 값을 조회값이라 부른다. 세 경로는 모두 이 조회값을 읽는다. 접수 배치는 여기서 포장이 끝나지 않은 배송단위(상태 `PLANNED`·`TOTE_ASSIGNED`·`PACKING`)에 배정된 수량을 뺀 가용 재고를 쓴다. 같은 조건의 수정 후 포장 부하 테스트(작업자 50명, 3분)에서 실패는 0, p95는 73ms, 데드락은 0이 됐다.

이 구조의 전제는 하나다. 집계가 늦어도 조회값은 정확해야 한다. 어느 행이 스냅샷에 들어갔든 아직이든, 둘을 합치면 원장 전체 합과 같아야 한다.

## 커서 결함이 깨는 것과 영향 크기

이 글에서 다루는 결함은 그 전제를 깬다. 집계기(원장 행을 주기적으로 합산해 스냅샷에 더하는 작업)는 원장 행을 id 순서로 집계한다. id를 받은 뒤 늦게 커밋한 행이 있으면, 그 행은 스냅샷에도 미집계 차분에도 들어가지 않는다. 포장 완료의 차감 행이 빠지면 조회값이 그 수량만큼 많아진다. 접수 배치가 그 값을 읽으면 없는 재고에 주문을 받는다. 이 주문은 피킹이나 포장 단계에서 결품으로 드러난다.

영향 크기는 세 값으로 가늠한다.

- **한 번의 오차**: 빠진 행의 수량만큼 조회값이 틀린다. 포장 완료 품목 1건이 1개면 1개다.
- **발생 빈도**: 누락은 집계 주기(5초)마다, 집계 시점에 원장 행을 넣고 아직 커밋하지 않은 포장 완료가 있을 때 생길 수 있다. 수정 후 포장 부하 테스트(작업자 50명, 3분)의 동시 진행 건수는 처리량 32.6건/s × 평균 소요 44.9ms(부하 테스트 도구 k6 측정) ≈ 1.5건이다. 진행 중인 건이 모두 누락된다고 가정하면 3분(36주기) 동안 약 54행, 완료 5,874건의 0.9%다. 평균값으로 계산한 추정치다. 실제 발생 수는 실측 필요 — 수정 전 빌드로 같은 부하를 주고 집계 주기마다 `inventory.reconcile.mismatch` 발생 수를 세야 한다(부하 환경이 다른 실험에 점유돼 미실행).
- **틀린 값이 유지되는 시간**: 대조기(스냅샷과 원장 전체 합을 비교해 어긋나면 스냅샷을 다시 쓰는 작업)가 없으면 영구히 남는다. 대조기가 있으면 다음 대조(주기 60초)에서 원장 전체 합으로 복구된다. 다만 대조 순간에 커밋 순서가 뒤바뀐 미커밋 행이 있으면 대조기도 그 행을 건너뛴다. 이 60초 안에 접수 배치가 들어오면 틀린 값으로 주문을 선별한다.

## 머지 전에 고친 이유

이 결함은 부하 테스트가 아니라 머지 전 코드 검토에서 지적됐다. 수정 후 포장 부하 테스트의 결과(불일치 0)는 수정 후 빌드의 값이라, 수정 전 코드에 결함이 없다는 증거가 되지 못한다. 방치하면 대조기가 60초마다 복구하고 다시 누락하는 일이 반복될 수 있다. 대조기 없이 운영하면 누락이 쌓인다. 수정은 스키마 마이그레이션 1건(V22)과 집계·대조 SQL의 조건 2개라서, 머지 전에 넣는 비용이 작았다.

이 글에서는 커서 구조와 결함 원인, psql 재현, 대조기의 복구 범위, 정착 윈도우 설계와 검증, 남은 과제까지를 다룬다.

## 원장·스냅샷·커서 구조

전제를 지키려면 집계기가 어느 행까지 집계했는지를 기록해야 한다. 그 기록이 커서다. `stock_balance`는 상품마다 `(qty, last_tx_id)` 한 행을 두고, `last_tx_id`가 커서다. `inventory_tx`는 입고·포장 차감·조정을 한 행씩 기록한다. 조회값은 다음 식으로 계산한다.

```
조회값 = stock_balance.qty + Σ inventory_tx.qty_delta (id > last_tx_id)
```

집계기 `StockBalanceCollector`는 5초마다 `id > last_tx_id`인 행을 상품별로 합산해 `qty`에 더한다. 그리고 `last_tx_id`를 그 행들의 최대 id로 옮긴다. 조회가 미집계 행을 항상 더하므로, 집계가 늦어도 값은 정확하다.

대조기 `StockReconciler`는 60초마다 상품별로 두 값을 비교한다. 하나는 조회값 식으로 계산한 값(스냅샷 + 미집계 차분), 다른 하나는 원장 전체 합이다. 다르면 지표 `inventory.reconcile.mismatch`에 올리고, 원장 전체 합으로 스냅샷을 다시 쓴다(`StockReconciler.REBUILD`). 원장은 고치지 않는다.

포장 완료 트랜잭션은 품목마다 원장에 차감 행을 넣으며 id를 받는다. 이어 박스 재고 행을 `FOR UPDATE`로 잠가 1개 차감하고, 토트(배송단위 하나의 상품을 담아 포장대로 옮기는 운반 상자)를 해제한 뒤 커밋한다. 상품 행은 잠그지 않는다.

## id 발급 시점과 커밋 시점의 차이

커서는 id로 기록하므로, id 순서와 커밋 순서가 같다고 가정한다. id는 INSERT가 실행되는 순간 시퀀스에서 발급된다. 행이 다른 트랜잭션에 보이는 시점은 커밋이다. 두 시점 사이에 지연이 들어가면 id 순서와 커밋 순서가 뒤바뀐다. `id > last_tx_id` 커서는 id가 큰 행이 나중에 보인다고 가정하므로, 뒤바뀐 행을 놓친다.

머지 전 최종 검토의 지적도 같았다. "id를 먼저 받고 늦게 커밋한 행은 커서가 이미 지나간 뒤라 영원히 접히지 않는다."

포장 작업자 A의 포장 완료가 원장에 id 4 행을 넣고 박스 재고 행의 락을 기다린다고 하자. 그사이 작업자 B의 포장 완료가 id 5를 받고, 락을 먼저 얻어 커밋한다. 이 시점에 집계기가 실행되면 보이는 행은 id 5뿐이어서 커서가 5로 이동한다. 뒤늦게 커밋된 id 4는 `id > 5`에 걸리지 않는다. 미집계 조회에도, 다음 집계에도 들어가지 않는다.

역전 경로는 박스 락 대기만이 아니다.

- **같은 박스의 락 대기**: 위 예다. 수정 후 포장 부하 테스트에서 RDS 락 대기 세션은 최대 2였다.
- **품목 수 차이**: 배송단위의 품목 수는 1~5개다(원장 전환 전 포장 부하 테스트의 분포). 품목 5개인 A가 첫 행을 넣은 뒤 나머지 4행을 넣는 동안, 품목 1개인 B가 더 큰 id로 먼저 커밋할 수 있다. 박스가 달라도 생긴다.
- **그 밖의 지연**: 애플리케이션과 DB 사이 네트워크 지연이나 JVM 일시정지도 INSERT와 커밋 사이를 벌린다.

운영 부하에서 어느 경로가 주로 생기는지는 실측 필요 — 포장 완료 트랜잭션의 첫 원장 INSERT 시각과 커밋 시각을 서버에서 기록해야 한다.

해결하려면 커서를 옮길 때 새 위치보다 작은 id의 미커밋 행이 없어야 한다. 이를 보장하는 방법은 뒤 절에서 다룬다.

## psql 세션 3개로 재현

가정이 깨지는 조건을 psql 세션 3개로 만들었다. 로컬 Docker의 PostgreSQL 18.6 컨테이너에 두 테이블만 만들었다. 원장 3행(입고 +100, 조정 −1, −6)을 넣고 스냅샷을 `(93, last 3)`으로 뒀다. 세션 A는 늦게 커밋하는 포장 완료, 세션 B는 바로 커밋하는 포장 완료, 세션 K는 집계기다. A의 박스 락 대기는 `pg_sleep(4)`로 흉내 냈다. 집계기 SQL은 수정 전 버전 그대로다.

```sql
-- 수정 전 집계기 SQL: 보이는 행의 MAX(id)까지 집계한다
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(t.id) FROM inventory_tx t
                      WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       computed_at = now()
 WHERE EXISTS (SELECT 1 FROM inventory_tx t
                WHERE t.product_id = b.product_id AND t.id > b.last_tx_id);
```

집계 1회차가 A의 id 4를 건너뛰고 커서를 5로 옮겼다. 세 세션의 사건을 시각 순으로 모았다.

| 시각(UTC) | 세션 | 사건 | 스냅샷 (qty, last) | 조회값 / 원장 전체 합 |
| --- | --- | --- | --- | --- |
| 07:12:12.695 | A | INSERT → id 4 (−1), `pg_sleep(4)` | (93, 3) | |
| 07:12:13.198 | B | INSERT → id 5 (−2), 바로 커밋 | | |
| 07:12:13.398 | K | 집계 1회차. 보이는 미집계 행은 id 5뿐, `UPDATE 1` | (91, 5) | 91 / 91 |
| 07:12:16.705 | A | 커밋 | | |
| 07:12:17.198 | K | 집계 2회차. 미집계 행 0 rows, `UPDATE 0` | (91, 5) | 91 / 90 |

집계 2회차의 로그다. A가 커밋한 id 4는 커서 5보다 작아 미집계 조회에 잡히지 않는다.

```
select id, qty_delta from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
 id | qty_delta 
----+-----------
(0 rows)

-- (수정 전 집계기 SQL 생략)
UPDATE 0
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
 qty | last_tx_id | on_hand_read | ledger_truth 
-----+------------+--------------+--------------
  91 |          5 |           91 |           90
(1 row)
```

*캡션: `on_hand_read`는 조회값, `ledger_truth`는 원장 전체 합이다. 원장 전체 합은 100 − 1 − 6 − 1 − 2 = 90인데 조회값은 91이다. id 4의 −1이 스냅샷에도 차분에도 없다.*

집계기만으로는 이 값이 돌아오지 않는다. 뒤의 집계는 모두 `UPDATE 0`이다.

누락은 다른 원인과 증상이 비슷하다. 판별 기준은 "id가 `last_tx_id` 이하인데 그 행의 차분이 스냅샷 `qty`에 없다"는 것이다. 스냅샷 `qty`와 커서까지의 원장 합(`id <= last_tx_id`인 행의 합)을 비교하면 된다. `id > last_tx_id` 여부만으로는 구분할 수 없다. 정상 집계된 id 5도 false다.

| 원인 | 스냅샷 qty와 커서까지의 원장 합 | 차이의 방향 |
| --- | --- | --- |
| 롤백으로 생긴 시퀀스 빈 번호 | 같다. 빈 번호에는 원장 행이 없다(추론, 미재현) | 없음 |
| 집계기 동시 실행 | 다르다 | 이미 더한 구간의 합이 이중 반영된다. 차감 행이면 재고가 적게 나온다(공통 테이블 식(CTE) SQL 재현에서 90, 정답 93) |
| 커밋 순서 역전 누락 | 다르다 | 빠진 행의 차분만큼 어긋난다. 차감 행이면 재고가 많게 나온다 |

## 대조기의 복구 범위

누락이 나면 대조기가 고치는지를 확인했다. 수정 전 대조기(커밋 `83dcf67`)의 `REBUILD`는 `qty`를 원장 전체 합으로, `last_tx_id`를 전체 `MAX(id)`로 다시 쓴다. 같은 세션 3개로 누락, 대조, 대조 중 역전을 이어서 실행했다. 표의 `derived`는 조회값, `ledger_total`은 원장 전체 합이다.

| 시각(UTC) | 세션 | 사건 | 스냅샷 (qty, last) | 조회값 / 원장 전체 합 |
| --- | --- | --- | --- | --- |
| 07:12:17.698 | K | 대조 1회차(미커밋 행 없음). 불일치 1건 `derived 91, ledger_total 90` → `REBUILD` | (90, 5) | 90 / 90 |
| 07:12:23.199 | A | INSERT → id 8 (−5), `pg_sleep(4)` | | |
| 07:12:23.695 | B | INSERT → id 9 (−3), 바로 커밋 | | |
| 07:12:23.899 | K | 대조 2회차(id 8 미커밋). 불일치 1건 `derived 83, ledger_total 80` → `REBUILD` | (80, 9) | 80 / 80 |
| 07:12:27.210 | A | 커밋 | | |
| 07:12:27.702 | K | 집계 4회차 `UPDATE 0`. 불일치 1건 `derived 80, ledger_total 75` | (80, 9) | 80 / 75 |
| 07:12:28.197 | K | 대조 3회차(미커밋 행 없음). `REBUILD` 뒤 불일치 0 rows | (75, 9) | 75 / 75 |

*캡션: 07:12:18~22 사이에 집계 3회차가 id 6을 건너뛰어 86 / 83이 된 구간은 표에서 뺐다. 전체 로그는 `docs/evidence/ledger-cursor/logs/r1-prefix-collector-reconciler.log`에 있다.*

대조기는 미커밋 원장 행이 없을 때 누락을 복구했다(대조 1회차, 3회차). 그러나 `REBUILD`도 보이는 행의 `MAX(id)`로 커서를 옮긴다. 대조 2회차는 미커밋 id 8을 건너뛰고 커서를 9로 옮겨, 대조 직후 다시 5가 어긋났다. 수정 전 코드의 누락은 집계기만 보면 영구적이고, 대조기를 포함하면 최대 60초 동안 틀리며, 대조 순간에 역전이 있으면 다시 틀린다.

## 정착 윈도우 설계

필요한 것은 "이 id보다 작은 미커밋 행이 없다"는 보장이다. 후보는 정착 윈도우와, 트랜잭션 ID(xid)로 커서를 두는 xid 커서 2가지다.

| 방식 | 내용 | 한계 | 판단 |
| --- | --- | --- | --- |
| 정착 윈도우 | INSERT된 지 W초가 지난 행까지만 집계한다 | "원장 쓰기 트랜잭션은 행을 넣은 뒤 W초 안에 끝난다"는 시간 가정에 기댄다 | 채택. 스키마 변경이 작고 가정이 명확하다 |
| xid 커서 | 행에 `xid8`을 기록하고, MVCC 스냅샷(SQL 문이 볼 수 있는 커밋 범위)의 `pg_snapshot_xmin`(아직 진행 중인 가장 오래된 xid) 이전 트랜잭션까지만 집계한다 | 커서를 id에서 xid로 바꿔야 한다. DB 안 긴 트랜잭션(예: 출고지시 접수 테스트의 272초 배치)이 `pg_snapshot_xmin`을 붙잡으면 그동안 집계가 멈춘다 | 보류 |

xid 커서는 폴링형 아웃박스에서 같은 문제를 푸는 방법으로 소개된다(https://event-driven.io/en/ordering_in_postgres_outbox/). 그 글도 긴 트랜잭션이 새 행의 처리를 늦춘다고 적는다.

정착 윈도우은 3가지 결정으로 만들었다.

1. **`created_at`은 PostgreSQL이 `clock_timestamp()`로 기록한다.** 스키마 마이그레이션 V22가 기본값을 `now()`에서 `clock_timestamp()`로 바꾼 스키마 변경이다. `now()`는 트랜잭션 시작 시각이고, `clock_timestamp()`는 함수가 호출된 실제 시각이다(https://www.postgresql.org/docs/18/functions-datetime.html). 트랜잭션 시작 시각을 쓰면, 일찍 시작해 늦게 INSERT하고 빨리 커밋한 행이 정착된 것으로 잘못 판정된다.
2. **기준 시각은 `statement_timestamp()`로 정한다.** 공식 문서상 현재 SQL 문의 시작 시각, 정확히는 클라이언트의 마지막 명령 메시지를 받은 시각이다. 한 SQL 문 안에서 값이 고정된다. 이 시각이 SQL 문의 MVCC 스냅샷을 잡기 전이라 판정이 보수적이라는 것은 문서 설명에서 추론한 것이다.
3. **윈도우 안의 행 가운데 가장 작은 id 앞까지만 집계한다.** 윈도우를 지난 행이라도, 그보다 작은 id의 행이 윈도우 안에 있으면 집계하지 않는다. `created_at`이 id 순서와 어긋나는 행을 막는다. 애플리케이션이 `created_at`을 명시해 넣은 행이나, V22 이전에 `now()`로 기록된 행이 해당한다.

```sql
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id AND t.id <= s.new_last),
       last_tx_id = s.new_last, computed_at = now()
  FROM (SELECT b2.product_id,
               (SELECT MAX(t.id) FROM inventory_tx t
                 WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id
                   AND t.created_at < statement_timestamp() - make_interval(secs => :settle)       -- (2)
                   AND t.id < COALESCE((SELECT MIN(y.id) FROM inventory_tx y                         -- (3)
                                         WHERE y.product_id = b2.product_id AND y.id > b2.last_tx_id
                                           AND y.created_at >= statement_timestamp() - make_interval(secs => :settle)),
                                       9223372036854775807)) AS new_last
          FROM stock_balance b2) s
 WHERE b.product_id = s.product_id AND s.new_last IS NOT NULL AND b.last_tx_id < s.new_last;
```

*캡션: `StockBalanceCollector.ADVANCE`. 코드의 `?::float8` 파라미터를 `:settle`로 적고 줄바꿈을 줄였다. 대조기 `REBUILD`에도 같은 두 조건을 넣었다.*

(2)와 (3)이 함께 있으면 집계 범위 안에 미커밋 행이 남지 않는다. 집계하는 마지막 행 X가 윈도우 W보다 오래됐다고 하자. X보다 작은 id를 받은 트랜잭션은 X보다 먼저 행을 넣었으므로, 행을 넣은 지 W가 지났다. 가정에 따라 그 트랜잭션은 이미 끝났고, 끝난 트랜잭션의 행은 이 SQL 문의 MVCC 스냅샷에 보인다.

이 논증에는 전제가 네 개 있다.

- **id가 INSERT 시점에 DB에서 발급된다.** `inventory_tx.id`는 `GENERATED BY DEFAULT AS IDENTITY`이고 엔티티는 `GenerationType.IDENTITY`다. `GenerationType.SEQUENCE`에 `allocationSize`가 1보다 크면, 애플리케이션이 id를 미리 받아 두므로 id 순서가 INSERT 순서와 떨어진다.
- **시퀀스 캐시가 1이다.** 세션마다 번호를 묶어 받으면(CACHE > 1) id 순서가 발급 순서를 따르지 않는다. IDENTITY 컬럼에 캐시 옵션을 주지 않았다.
- **세션 시간대가 같다.** `created_at`은 시간대 없는 `TIMESTAMP`라서, 쓰는 세션과 집계 세션의 `TimeZone`이 다르면 비교가 어긋난다.
- **`nextval`과 `clock_timestamp()` 사이의 틈을 무시한다.** 한 INSERT 안에서 두 기본값이 평가되는 사이의 틈(미측정)만큼 가정이 느슨해진다.

윈도우는 60초로 정했다. 수정 후 포장 부하 테스트에서 포장 완료 요청의 k6 소요는 p50 35ms, p95 73ms, max 999ms였다. max는 시작 직후 커넥션 대기가 몰린 구간을 포함한 값이다. 포장 완료 외의 원장 쓰기 경로(`StockInService`의 입고 기록, 조정 API의 `adjust`, 시연 리셋의 `adjustInternal`)의 소요는 실측 필요 — 각 경로의 원장 INSERT부터 커밋까지 시간을 기록해야 한다.

조회값 식은 여전히 `id > last_tx_id`인 행을 더하므로, 윈도우를 두어도 조회값은 늦어지지 않는다. 늦어지는 것은 스냅샷뿐이고, 그만큼 조회의 차분 쿼리가 최근 60초 치 행을 더 읽는다.

## 검증

같은 세션 3개를 수정 후 SQL로 다시 실행했다. 세션 A는 행을 넣고 4초 뒤 커밋한다. 윈도우를 5초로 두면 가정을 지키고, 3초로 두면 어긴다. 두 실행은 같은 스크립트이고 윈도우 값만 다르다.

| 시각(초, A INSERT 기준) | 사건 | 윈도우 5초 | 윈도우 3초(가정 위반 비교군) |
| --- | --- | --- | --- |
| 0.0 | A INSERT → id 4 (−1) | | |
| 0.5 | B INSERT → id 5 (−2), 바로 커밋 | | |
| 0.7 | 집계 1회차 (id 5 나이 약 0.2초) | `UPDATE 0`, 조회 91 / 91 | `UPDATE 0`, 조회 91 / 91 |
| 3.7 | 집계 2회차 (A 미커밋, id 5 나이 약 3.2초) | `UPDATE 0`, 조회 91 / 91 | `UPDATE 1`, 커서 5로 이동 |
| 4.0 | A 커밋 | | |
| 6.0 | 집계 3회차 | `UPDATE 1`, (90, 5), 조회 90 / 90 | `UPDATE 0`, 조회 91 / 90 |

*캡션: 윈도우 5초 로그 `docs/evidence/ledger-cursor/logs/r2-settle5-wait4.log`(07:12:30~36 UTC), 윈도우 3초 로그 `r2-settle3-wait4-control.log`(07:12:38~44 UTC).*

윈도우 5초의 집계 2회차 로그다. id 5가 윈도우 안에 있어 집계하지 않는다.

```
select id, qty_delta, round(extract(epoch from statement_timestamp() - created_at)::numeric, 3) as age_s from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
 id | qty_delta | age_s 
----+-----------+-------
  5 |        -2 | 3.195
(1 row)

-- (수정 후 집계기 SQL 생략)
UPDATE 0
```

가정을 지키면 A가 열려 있는 동안 스냅샷은 그대로이고, 조회값은 커밋된 행 기준으로 정확했다. A가 커밋하고 윈도우가 지난 3회차에서 id 4와 5가 함께 집계돼 90 / 90이 됐다. 가정을 어기면 수정 후 SQL도 누락을 낸다. 윈도우 3초의 2회차는 A가 아직 열려 있는데 id 5를 집계했고, 최종 조회값은 91, 원장 전체 합은 90이었다. 판별 쿼리로 보면 윈도우 5초는 스냅샷 90 = 커서까지의 원장 합 90, 윈도우 3초는 91 ≠ 90이다.

같은 상황을 통합 테스트(Integration Test, 클래스명 접미사 IT)로도 확인했다. `StockBalanceCollectorSettleIT`는 한 스레드가 트랜잭션 안에서 행을 넣고 래치로 대기하는 동안, 다른 행을 커밋하고 집계기를 호출한다. 윈도우 5초에서 통과했다(`tests="1" failures="0"`). 윈도우 설정만 0으로 바꾼 임시 사본(`StockBalanceCollectorSettleProbeIT`)은 수정 전 결함을 그대로 재현했다.

```
StockBalanceCollectorSettleProbeIT > 커밋_순서가_뒤바뀐_원장_행도_빠지지_않는다() FAILED
    java.lang.AssertionError at StockBalanceCollectorSettleProbeIT.java:82

BUILD FAILED in 14s
-- 테스트 결과 XML의 failure 본문
Expecting actual:
  2L
to be less than:
  1L 
```

*캡션: 82행은 `assertThat(duringOpenTx.lastTxId()).isLessThan(slowIdHolder.get())`이다. 미커밋 id 1을 건너뛰고 커서가 2로 이동했다는 실패다.*

수정 후 포장 부하 테스트는 원장 전환 전 포장 부하 테스트와 같은 시나리오(포장 작업자 50명, 3분)로 했다. 포장 완료 5,874건이 모두 성공했고 데드락은 0건이었다. 실행이 끝난 뒤 원장의 포장 차감 합과 `PACKED` 배송단위 품목 합은 47,662로 같았다. 스냅샷에 차분을 더한 값과 원장 전체 합의 불일치도 0이었다. 실행 중 미집계 행은 최대 7,134개(윈도우 안의 행)였고, `lag_seconds`(가장 오래된 미집계 원장 행의 나이, 초)는 60을 유지했다. 수정 전 커서 코드로는 같은 부하를 주지 않았으므로, 이 결과는 수정 전후 비교가 아니다.

## 결론

포장 완료 실패 40.4%를 0으로 만든 원장 전환이, 집계 커서 한 줄 때문에 조회값을 실제보다 많게 보일 수 있었다. 정착 윈도우으로 그 경로를 막았고, 남은 것은 60초 가정을 강제할 수단과 수정 전 빌드에서의 실측이다. 로컬 재현에서 윈도우 5초는 90 / 90, 가정을 어긴 윈도우 3초는 91 / 90이었다.

같은 누락은 시퀀스 id를 증분 커서로 쓰고, 여러 트랜잭션이 동시에 행을 넣으며, INSERT와 커밋 사이에 지연이 있는 설계에서 생긴다. id로 폴링하는 아웃박스, 변경 로그를 마지막 id 이후부터 읽는 증분 동기화가 해당한다. 쓰기가 한 번에 한 트랜잭션으로 직렬화돼 있거나, Write-Ahead Log(WAL) 논리 디코딩으로 변경을 받는 Change Data Capture(CDC)처럼 커밋 순서로 변경을 받는 경우는 해당하지 않는다.

비슷한 커서를 쓴다면 세 가지를 점검한다.

- 커서가 시퀀스 id인가.
- INSERT와 커밋 사이에 락 대기나 다른 작업이 있는가.
- 스냅샷을 원장 전체 합으로 다시 쓰는 복구 경로(`REBUILD`)가 있다면, 그 경로도 같은 커서 규칙을 쓰는가.

## 남은 과제

- **60초 가정을 강제할 수단이 없다.** 원장 쓰기 트랜잭션이 60초 안에 끝난다는 가정은 코드로 검사하지 않는다. PostgreSQL 17 이상의 `transaction_timeout`으로 DB에서 강제할 수 있다(https://www.postgresql.org/docs/18/runtime-config-client.html). RDS는 `infra/variables.tf`의 `rds_engine_version`이 `"18"`이라 쓸 수 있다. 시간을 넘기면 SQL 문만 취소되지 않고 세션이 종료된다. 애플리케이션의 DB 역할(role) 전체에 걸면 출고지시 접수 테스트의 272초 배치도 끊기므로, 원장 쓰기 트랜잭션에만 적용해야 한다. 적용 방법(트랜잭션 안 설정 또는 전용 DB 역할)은 동작 확인 필요. 가정이 깨지면 대조기가 60초 안에 복구하지만, 복구 전까지 조회값은 틀린다.
- **수정 전 빌드의 누락 빈도를 재지 않았다.** 실측 필요 — 수정 전 빌드로 같은 부하에서 집계 주기마다 `inventory.reconcile.mismatch` 발생 수(부하 환경 점유 중이라 미실행).
- **서버를 2대로 늘리면 집계기의 동시 실행을 조정해야 한다.** ShedLock으로 한 번에 한 인스턴스만 집계기를 실행하는 방안을 계획하고 있다. 현재 SQL은 동시에 실행돼도 이중 반영이 없다. `StockBalanceCollectorIT.동시_집계와_동시_원장_추가에서도_스냅샷은_원장_합과_같다`(집계 스레드 2개 × 15회, 삽입 30건)가 이를 확인한다.
- **정착 윈도우의 비용은 윈도우 안의 행 수다.** 정착 윈도우의 약점은 시간 가정이다. 쓰기량이 늘면 조회마다 더 읽는 윈도우 안의 행이 늘어난다. 수정 후 포장 부하 테스트에서 최대 7,134행이었다. 이 값이 조회 시간을 끌어올리면 xid 커서를 다시 검토한다.
