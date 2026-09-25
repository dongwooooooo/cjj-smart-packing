# 원장 커서가 놓친 한 줄 — id 순서와 커밋 순서가 다를 때

> 초안 v1 (2026-09-25). 독자: 백엔드 개발자. 종결 `~다`. 근거: `docs/evidence/loadtest/ledger-review-repro.md`, 실행 5.

포장 완료 트랜잭션이 상품 행을 잠근 채 서로를 기다리는 데드락을 없애려고 재고를 원장 방식으로 바꿨다. 잔고는 원장을 5초마다 집계한 스냅샷에, 아직 집계하지 않은 원장 행을 더해 계산한다. 이 글에서는 집계 위치를 기록하는 커서가 정상 부하에서 원장 한 줄을 영구히 누락하는 결함을 다룬다. 코드 검토에서 결함을 발견해 psql 세션 3개로 재현했고, 정착 창을 두어 고친 뒤 같은 부하로 확인했다.

## 원장·스냅샷·커서 구조

재고는 두 테이블로 표현한다. `inventory_tx`는 입고·포장 차감·조정을 한 행씩 기록하는 원장이다. `stock_balance`는 상품마다 `(qty, last_tx_id)` 한 행을 두는 스냅샷이다. 실재고는 다음 식으로 계산한다.

```
실재고 = stock_balance.qty + Σ inventory_tx.qty_delta (id > last_tx_id)
```

집계기 `StockBalanceCollector`는 5초마다 `id > last_tx_id`인 행을 상품별로 합산해 `qty`에 더하고, `last_tx_id`를 그 행들의 최대 id로 갱신한다. 스냅샷은 성능을 위한 캐시일 뿐이다. 조회가 미집계 행을 항상 더하므로 집계가 늦어도 값은 정확하다. 원장 설계는 이 성질을 전제로 했다.

포장 완료 트랜잭션은 품목마다 원장에 차감 행을 넣으며 id를 발급받는다. 이어 박스 재고 행을 `FOR UPDATE`로 잠가 1개 차감하고, 토트를 해제한 뒤 커밋한다. 상품 행은 더 이상 잠그지 않는다.

## id 순서와 커밋 순서가 어긋나는 문제

머지 전 최종 검토에서 다음 지적이 나왔다. "id를 먼저 받고 늦게 커밋한 행은 커서가 이미 지나간 뒤라 영원히 접히지 않는다."

포장 작업자 A가 포장 완료를 처리하면 Spring 서버는 원장에 id 4 행을 넣고 박스 재고 행의 락을 기다린다. 그사이 작업자 B의 포장 완료가 id 5를 받고, 락을 먼저 얻어 커밋한다. 이 시점에 집계기가 실행되면 보이는 행은 id 5뿐이어서 커서가 5로 이동한다. 뒤늦게 커밋된 A의 id 4는 `id > 5` 조건에 맞지 않아 미집계 조회에도, 다음 집계에도 포함되지 않는다. 스냅샷에도 차분에도 없으므로 A의 차감은 실재고 계산에서 빠진다.

같은 박스를 쓰는 작업자 50명이 박스 재고 행의 락을 기다리면 커밋 순서는 락을 얻은 순서가 된다. 부하 테스트에서 포장 완료 요청 한 건의 소요 시간은 k6 기준 최대 999ms였고, 집계기는 5초마다 실행된다. 따라서 집계 주기마다 원장 행을 넣고 아직 커밋하지 않은 포장 완료가 존재할 가능성이 높다.

## psql 세션 3개로 재현

PostgreSQL 18.6 컨테이너에 두 테이블만 만들고 스냅샷을 `(93, last 3)`으로 둔 뒤, 세션 3개의 실행 시간을 겹쳤다. 세션 A는 포장 완료 1, 세션 B는 포장 완료 2, 나머지 세션은 집계기 역할이다. 집계기 SQL은 수정 전 버전이다.

```sql
-- 수정 전 집계 SQL: 보이는 행의 MAX(id)까지 접는다
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(qty_delta),0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(id) FROM inventory_tx t
                      WHERE t.product_id = b.product_id AND t.id > b.last_tx_id)
 WHERE EXISTS (SELECT 1 FROM inventory_tx t
                WHERE t.product_id = b.product_id AND t.id > b.last_tx_id);
```

세션별 출력을 시각 순으로 나열했다.

```
--- 세션 A (포장 완료 1)
begin;
 05:52:20.416
insert into inventory_tx(product_id, qty_delta) values (1,-1) returning id;
  4
select pg_sleep(4);          -- 박스 행 락을 기다리는 시간
commit;
 05:52:24.426 | A 커밋 완료

--- 세션 B (포장 완료 2)
 05:52:21.441
insert into inventory_tx(product_id, qty_delta) values (1,-2) returning id;
  5                          -- 즉시 커밋

--- 집계기 1회차 (05:52:21.516, A 커밋 전)
select id, qty_delta from inventory_tx where id > (select last_tx_id from stock_balance);
  5 |        -2               -- id 4 는 아직 안 보인다
UPDATE 1
 qty | last_tx_id
  91 |          5             -- 커서가 4 를 건너뛰고 5 로

--- 집계기 2회차 (05:52:24.504, A 커밋 후)
select id, qty_delta from inventory_tx where id > (select last_tx_id from stock_balance);
(0 rows)                     -- id 4 는 5 보다 작아 미집계로 안 잡힘
UPDATE 0

=== 최종
 on_hand_read | ledger_truth
           91 |           90
 id | qty_delta | visible_to_reads
  4 |        -1 | f
```

원장 합은 90인데 조회값은 91이다. id 4의 −1은 스냅샷에도 차분에도 반영되지 않았다. 마지막 행의 `visible_to_reads = f`가 이 결함을 나타낸다. 커밋된 행인데 조회 식의 범위에 들어가지 않는다. 수정 전에는 대조기 `StockReconciler`의 재작성(REBUILD)도 같은 커서 규칙(`MAX(id)`)을 썼으므로 이 값을 바로잡지 못했다.

## id 발급 시점과 커밋 시점의 차이

id는 INSERT 문이 실행되는 순간 시퀀스에서 발급된다. 행이 다른 트랜잭션에 보이는 시점은 커밋이다. 두 시점 사이에 락 대기 같은 지연이 들어가면 id 순서와 커밋 순서가 뒤바뀐다. `id > last_tx_id` 커서는 id가 큰 행이 나중에 보인다고 전제하지만, 커밋 순서에서는 이 전제가 성립하지 않는다.

같은 문제는 시퀀스 id를 증분 커서로 쓰는 모든 설계에서 발생한다. 이벤트 테이블을 id로 폴링하는 아웃박스, 변경 로그를 마지막 id 이후부터 읽는 동기화가 모두 해당한다.

## 정착 창 도입

커서를 이동할 때는 새 위치보다 작은 id를 가진 미커밋 행이 없어야 한다. 이를 보장할 방법으로 후보 2가지를 비교했다.

| 방식 | 내용 | 판단 |
| --- | --- | --- |
| 정착 창 | INSERT된 지 W초가 지난 행까지만 집계한다. 전제: 원장에 쓰는 트랜잭션은 행을 넣은 뒤 W초 안에 끝난다 | 채택. 스키마 변경이 작고 전제가 명확하다 |
| xid 커서 | 행에 `xid8`을 기록하고 `pg_snapshot_xmin` 이전 트랜잭션까지만 집계한다 | 보장은 엄밀하지만 커서를 id에서 xid로 바꿔야 해서 변경 범위가 크다 |

정착 창은 3가지 결정으로 구현했다.

1. **`created_at`은 PostgreSQL이 `clock_timestamp()`로 기록한다.** 이 값은 INSERT가 실행된 순간의 시각이고, `now()`는 트랜잭션 시작 시각이다. 트랜잭션 시작 시각을 기준으로 삼으면 일찍 시작해 늦게 INSERT하고 빨리 커밋한 행이 정착된 것으로 잘못 판정된다.
2. **기준 시각은 `statement_timestamp()`로 정한다.** 한 SQL 문 안에서 값이 고정되고, 스냅샷을 획득하기 전 시각이어서 판정이 보수적이다.
3. **창 안의 행 중 가장 작은 id 앞까지만 집계한다.** 창을 지난 행이라도 그보다 작은 id를 가진 행이 창 안에 있으면 집계하지 않는다.

```sql
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id
                         AND t.id > b.last_tx_id AND t.id <= s.new_last),
       last_tx_id = s.new_last, computed_at = now()
  FROM (SELECT b2.product_id,
               (SELECT MAX(t.id) FROM inventory_tx t
                 WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id
                   AND t.created_at < statement_timestamp() - make_interval(secs => :settle)
                   AND t.id < COALESCE((SELECT MIN(y.id) FROM inventory_tx y
                                         WHERE y.product_id = b2.product_id AND y.id > b2.last_tx_id
                                           AND y.created_at >= statement_timestamp() - make_interval(secs => :settle)),
                                       9223372036854775807)) AS new_last
          FROM stock_balance b2) s
 WHERE b.product_id = s.product_id AND s.new_last IS NOT NULL AND b.last_tx_id < s.new_last;
```

이 조건이면 집계 범위 안에 미커밋 행이 남지 않는다. 집계하는 마지막 행 X가 창 W보다 오래됐다면, X보다 작은 id를 받은 트랜잭션도 행을 넣은 지 W가 지났다. 전제에 따라 그 트랜잭션은 이미 끝났고, 끝난 트랜잭션의 행은 이 SQL 문의 스냅샷에 보인다.

창은 60초로 정했다. 포장 완료는 약 1초 걸리므로 여유가 크다. 조회 식은 여전히 `id > last_tx_id`인 행을 더하므로 창을 두어도 조회값은 지연되지 않는다. 지연되는 것은 스냅샷뿐이고, 그만큼 차분 쿼리가 최근 60초 치 행을 더 읽는다.

## 검증

같은 세션 3개를 수정 후 SQL(창 3초)로 다시 실행했다.

```
--- 세션 A: 06:13:24.677 insert → id 1, 4초 대기 후 06:13:28.692 COMMIT
--- 세션 B: 06:13:25.681 insert → id 2, 즉시 커밋

--- 집계기 1회차 (06:13:25.780, A 커밋 전)
UPDATE 0                     -- id 2 는 1초 전 행, 창 안이라 접지 않는다
 qty | last_tx_id | on_hand_read
 100 |          0 |           98   -- 조회는 커밋된 id 2 만 더해 정확

--- 집계기 2회차 (06:13:28.884, A 커밋 직후, 두 행 모두 3초 경과)
UPDATE 1
  97 |          2 |           97   -- id 1 과 2 를 함께 접는다

=== 원장 진실
 ledger_truth
           97
```

1회차 집계는 창 안의 행을 반영하지 않아 `UPDATE 0`이었고, 그동안에도 조회값은 98로 정확했다. A가 커밋하고 창이 지난 2회차에서 두 행이 함께 집계돼 스냅샷과 원장이 97로 일치했다.

같은 상황을 통합 테스트로도 재현해 두었다. `StockBalanceCollectorSettleIT`에서는 한 스레드가 트랜잭션 안에서 행을 넣고 래치로 대기하는 동안, 다른 행을 커밋하고 집계기를 호출한다. 같은 테스트를 정착 창 0으로 실행한 사본(`StockBalanceCollectorSettleProbeIT`)에서는 수정 전 결함이 그대로 재현된다.

```
StockBalanceCollectorSettleProbeIT > 커밋_순서가_뒤바뀐_원장_행도_빠지지_않는다() FAILED
    java.lang.AssertionError:
    Expecting actual:
      2L
    to be less than:
      1L
    at ...StockBalanceCollectorSettleProbeIT.java:82
BUILD FAILED in 18s
```

`last_tx_id`가 아직 커밋되지 않은 id 1을 건너뛰고 2로 이동했다는 단언 실패다. 창을 5초로 두면 통과한다.

배포 뒤 같은 부하(포장 작업자 50명, 3분)로 확인했다. 포장 완료 5,874건이 모두 성공했고 데드락은 0건이었다. 실행이 끝난 뒤 원장의 포장 차감 합과 `PACKED` 배송단위 품목 합은 47,662로 같았다. 스냅샷에 차분을 더한 값과 원장 전체 합 사이의 불일치도 0이었다. 실행 중 미집계 행은 최대 7,134개(창 안의 행)였고, `lag_seconds`는 60을 유지했다.

## 남은 과제

- **60초 전제를 강제할 수단이 아직 없다.** 원장 쓰기 트랜잭션이 60초 안에 끝난다는 전제는 코드로 검사되지 않는다. PostgreSQL 18의 `transaction_timeout`을 앱 롤에 설정하면 이 전제를 DB 설정으로 강제할 수 있다. 전제가 깨져도 대조기 `StockReconciler`가 60초마다 원장 전체 합과 비교해 복구한다. 다만 복구 전까지 조회값은 틀린다.
- **서버를 2대로 늘리면 집계기의 동시 실행을 조정해야 한다.** 인스턴스마다 스케줄러를 실행하지 않고, ShedLock으로 한 번에 한 인스턴스만 집계기를 실행한다. 현재 SQL은 동시에 실행돼도 이중 반영이 없지만, 이는 2차 방어에 해당한다.
- **커서를 xid로 바꾸는 안**은 정착 창의 시간 가정 없이 같은 보장을 제공한다. 원장 쓰기가 초당 수백 건을 넘으면 다시 검토한다.
