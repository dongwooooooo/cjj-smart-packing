# 원장 기반 재고 — 검토가 잡은 결함 4건의 시나리오 코드와 실행 로그 (2026-09-25)

임시 PostgreSQL 18.6 컨테이너(psql, 세션 3개 동시 실행)와 수정 전 커밋 워크트리에서 실행한 그대로다. 각 절은 시나리오 코드 → 실행 과정 로그 → 결과 → 원인 → 수정 순서다.

## 1. 계획의 CTE 집계 SQL — 동시 집계 이중 반영

### 시나리오 코드
세션 C1(집계기 1): 트랜잭션을 열고 CTE UPDATE 실행 뒤 4초 대기 후 커밋. 세션 W: 그사이 원장 행 추가. 세션 C2(집계기 2): 같은 CTE UPDATE 실행(C1의 행 락을 기다린 뒤 재검사).

```sql
-- 세션 C1
\echo '[C1] 시작' 
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
begin;
WITH d AS (SELECT t.product_id, SUM(t.qty_delta) AS delta, MAX(t.id) AS max_id
           FROM inventory_tx t JOIN stock_balance b ON b.product_id = t.product_id
           WHERE t.id > b.last_tx_id GROUP BY t.product_id)
UPDATE stock_balance b SET qty = b.qty + d.delta, last_tx_id = d.max_id
  FROM d WHERE b.product_id = d.product_id AND b.last_tx_id < d.max_id;
select 'C1 트랜잭션 안에서 본 스냅샷' as note, qty, last_tx_id from stock_balance;
select pg_sleep(4);
commit;
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'C1 커밋 완료' as note;

-- 세션 C2
\echo '[C2] 시작 — C1 이 커밋 전이라 행 락 대기에 들어간다'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
WITH d AS (SELECT t.product_id, SUM(t.qty_delta) AS delta, MAX(t.id) AS max_id
           FROM inventory_tx t JOIN stock_balance b ON b.product_id = t.product_id
           WHERE t.id > b.last_tx_id GROUP BY t.product_id)
UPDATE stock_balance b SET qty = b.qty + d.delta, last_tx_id = d.max_id
  FROM d WHERE b.product_id = d.product_id AND b.last_tx_id < d.max_id;
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'C2 UPDATE 끝(락 풀린 뒤 재검사 통과)' as note;
```

### 실행 과정 로그
```
=== 초기 상태
select * from stock_balance;
 product_id | qty | last_tx_id 
------------+-----+------------
          1 | 100 |          0
(1 row)

select id, qty_delta from inventory_tx order by id;
 id | qty_delta 
----+-----------
  1 |        -1
  2 |        -2
(2 rows)

--- 세션 C1
\echo '[C1] 시작' 
[C1] 시작
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
      t       
--------------
 05:52:16.061
(1 row)

begin;
BEGIN
WITH d AS (SELECT t.product_id, SUM(t.qty_delta) AS delta, MAX(t.id) AS max_id
           FROM inventory_tx t JOIN stock_balance b ON b.product_id = t.product_id
           WHERE t.id > b.last_tx_id GROUP BY t.product_id)
UPDATE stock_balance b SET qty = b.qty + d.delta, last_tx_id = d.max_id
  FROM d WHERE b.product_id = d.product_id AND b.last_tx_id < d.max_id;
UPDATE 1
select 'C1 트랜잭션 안에서 본 스냅샷' as note, qty, last_tx_id from stock_balance;
             note             | qty | last_tx_id 
------------------------------+-----+------------
 C1 트랜잭션 안에서 본 스냅샷 |  97 |          2
(1 row)

select pg_sleep(4);
 pg_sleep 
----------
 
(1 row)

commit;
COMMIT
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'C1 커밋 완료' as note;
      t       |     note     
--------------+--------------
 05:52:20.075 | C1 커밋 완료
(1 row)

--- 세션 W
[W] 그사이 원장 id3(-4) 커밋
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
      t       
--------------
 05:52:17.087
(1 row)

insert into inventory_tx(product_id, qty_delta) values (1,-4) returning id;
 id 
----
  3
(1 row)

--- 세션 C2
\echo '[C2] 시작 — C1 이 커밋 전이라 행 락 대기에 들어간다'
[C2] 시작 — C1 이 커밋 전이라 행 락 대기에 들어간다
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
      t       
--------------
 05:52:17.169
(1 row)

WITH d AS (SELECT t.product_id, SUM(t.qty_delta) AS delta, MAX(t.id) AS max_id
           FROM inventory_tx t JOIN stock_balance b ON b.product_id = t.product_id
           WHERE t.id > b.last_tx_id GROUP BY t.product_id)
UPDATE stock_balance b SET qty = b.qty + d.delta, last_tx_id = d.max_id
  FROM d WHERE b.product_id = d.product_id AND b.last_tx_id < d.max_id;
UPDATE 1
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'C2 UPDATE 끝(락 풀린 뒤 재검사 통과)' as note;
      t       |                 note                 
--------------+--------------------------------------
 05:52:20.081 | C2 UPDATE 끝(락 풀린 뒤 재검사 통과)
(1 row)

=== 최종 상태
select qty, last_tx_id, 100 + (select sum(qty_delta) from inventory_tx where product_id=1) as correct_qty from stock_balance;
 qty | last_tx_id | correct_qty 
-----+------------+-------------
  90 |          3 |          93
(1 row)

```

### 결과
정답은 100 − 1 − 2 − 4 = 93인데 90이다. C1이 05:52:16에 id1·2를 접어 (97, last 2)로 만들고 커밋을 미루는 동안, C2는 05:52:17에 시작해 CTE `d`를 (delta −7, max_id 3)으로 계산하고 행 락을 기다렸다. C1이 05:52:20에 커밋하자 C2는 재검사에서 `b.last_tx_id(2) < d.max_id(3)`이 참이라 통과했고, 미리 계산한 −7을 통째로 더했다. id1·2가 두 번 반영됐다.

### 수정
상관 서브쿼리 UPDATE. SET 서브쿼리가 `b.last_tx_id`를 참조하므로 재검사 때 최신 커서(2) 기준 잔여분(id3, −4)만 더한다. 검증: `StockBalanceCollectorIT.동시_집계와_동시_원장_추가에서도_스냅샷은_원장_합과_같다`(집계 스레드 2개 × 15회 + 삽입 스레드 30건).

## 2. 대조기 — 한 상품 실패가 전체 복구를 롤백

### 시나리오 코드
수정 전 커밋 3b17927 워크트리에 탐침 테스트를 넣었다. `MISMATCHES`가 상품 1·2 두 행을 돌려주고, 상품 1의 REBUILD는 예외를 던지고, 상품 2의 REBUILD는 성공하는 상황.

```java
when(jdbc.queryForList(StockReconciler.MISMATCHES)).thenReturn(rows);           // 상품 1, 2 불일치
doThrow(new DataAccessResourceFailureException("boom: 상품 1 REBUILD 실패"))
        .when(jdbc).update(eq(StockReconciler.REBUILD), eq(1L), eq(1L), eq(1L));
doReturn(1).when(jdbc).update(eq(StockReconciler.REBUILD), eq(2L), eq(2L), eq(2L));

int fixed = reconciler.reconcileOnce();

verify(jdbc).update(eq(StockReconciler.REBUILD), eq(2L), eq(2L), eq(2L));      // 상품 2는 복구돼야 한다
assertThat(fixed).isEqualTo(1);
assertThat(registry.get("inventory.reconcile.mismatch").gauge().value()).isEqualTo(2.0);
```

### 실행 결과 (수정 전 코드)
```
gradle exit=1
상품1_복구가_실패해도_상품2는_복구되고_지표는_갱신된다() FAIL
   type: org.springframework.dao.DataAccessResourceFailureException
   message: boom: 상품 1 REBUILD 실패
   at org.springframework.jdbc.core.JdbcTemplate.update(JdbcTemplate.java:1020)
   at com.awesome.backend.inventory.service.StockReconciler.reconcileOnce(StockReconciler.java:74)
```

### 원인
`reconcileOnce()`가 `@Transactional` 메서드 하나 안의 for 루프였다. 상품 1의 예외가 그대로 빠져나가 상품 2의 REBUILD는 호출조차 되지 않았고, 지표 갱신 줄에도 도달하지 못했다. 실제 DB였다면 트랜잭션 전체가 롤백돼 앞서 복구한 상품까지 되돌아간다.

### 수정
상품마다 `TransactionTemplate`로 별도 트랜잭션 + try/catch. 지표는 루프 밖에서 무조건 갱신. 같은 테스트가 수정 후 `StockReconcilerTest`로 통과.

## 3. 같은 멱등 키 동시 요청 — 500

### 시나리오 코드
수정 전 커밋 f94c4b4 워크트리에서 `InventoryAdjustmentControllerIT.같은_키_동시_요청은_한_건만_기록되고_전부_200이다` 실행. 스레드 8개가 래치로 동시에 같은 본문을 POST.

```java
String body = """
        {"gtin":"%s","delta":3,"idempotencyKey":"%s","reason":"동시성 테스트"}""".formatted(CIDER, key);
// 8 스레드가 start 래치를 기다렸다가 동시에 post(body)
assertThat(responses).allSatisfy(r -> assertThat(r.statusCode()).isEqualTo(200));
assertThat(parsed.stream().map(InventoryAdjustmentResponse::txId).distinct()).hasSize(1);
assertThat(parsed.stream().filter(r -> !r.duplicated())).hasSize(1);
assertThat(stock.onHand(CIDER)).isEqualTo(13);
```

### 실행 결과 (수정 전 코드)
```
gradle exit=1
suite InventoryAdjustmentControllerIT tests 4 failures 1 errors 0
 - 같은_키_동시_요청은_한_건만_기록되고_전부_200이다() FAIL
   Expecting all elements of:
     [(POST .../api/v1/admin/inventory/adjustments) 500,
      (POST .../api/v1/admin/inventory/adjustments) 200,
      (POST .../api/v1/admin/inventory/adjustments) 500,
      ... 500, 500, 500, 500, 500]
   expected: 200  but was: 500
서버 로그:
   WARN [o-auto-1-exec-1] org.hibernate.orm.jdbc.error : ERROR: duplicate key value violates unique constraint "ux_inventory_tx_idem"
   WARN [o-auto-1-exec-6] org.hibernate.orm.jdbc.error : ERROR: duplicate key value violates unique constraint "ux_inventory_tx_idem"
   (같은 줄 7건)
```

### 원인
8건 모두 `findByIdempotencyKey`를 빈 값으로 통과했다. 첫 INSERT만 성공하고 나머지 7건은 부분 유니크 인덱스에 걸렸는데, 핸들러가 `DataIntegrityViolationException`을 몰라 `INTERNAL_ERROR` 500으로 냈다. 재전송 클라이언트가 보기엔 실패다.

### 수정
`adjust`를 트랜잭션 밖(`NOT_SUPPORTED`)에서 돌려 유니크 위반 뒤 같은 키를 다시 읽고 `duplicated: true`로 답한다. 수정 후 같은 테스트: 8건 전부 200, txId 1개, `duplicated:false` 1건, 재고 +3 한 번.

## 4. id 커서 — id를 먼저 받고 늦게 커밋한 행 영구 누락 (최종 검토 C1)

### 시나리오 코드
세션 A(포장 완료 1): 원장 행 INSERT 뒤 4초 대기 후 커밋 — 포장 완료가 원장 행을 넣고 박스 행 락을 기다리는 상황. 세션 B(포장 완료 2): 원장 행 INSERT 즉시 커밋. 집계기: 정착 창이 없는 수정 전 SQL을 A 커밋 전과 후에 한 번씩.

```sql
-- 세션 A
\echo '[A] 포장 완료 트랜잭션: 원장 행 INSERT 뒤 박스 락 대기(4초)'
begin;
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
insert into inventory_tx(product_id, qty_delta) values (1,-1) returning id;
select pg_sleep(4);
commit;
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'A 커밋 완료' as note;

-- 집계기(수정 전 SQL)
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
select id, qty_delta from inventory_tx where product_id=1 and id > (select last_tx_id from stock_balance) order by id;
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(qty_delta),0) FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(id) FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id)
 WHERE EXISTS (SELECT 1 FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id);
select qty, last_tx_id from stock_balance;
```

### 실행 과정 로그
```
=== 초기 상태
select * from stock_balance;
 product_id | qty | last_tx_id 
------------+-----+------------
          1 |  93 |          3
(1 row)

--- 세션 A
\echo '[A] 포장 완료 트랜잭션: 원장 행 INSERT 뒤 박스 락 대기(4초)'
[A] 포장 완료 트랜잭션: 원장 행 INSERT 뒤 박스 락 대기(4초)
begin;
BEGIN
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
      t       
--------------
 05:52:20.416
(1 row)

insert into inventory_tx(product_id, qty_delta) values (1,-1) returning id;
 id 
----
  4
(1 row)

INSERT 0 1
select pg_sleep(4);
 pg_sleep 
----------
 
(1 row)

commit;
COMMIT
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'A 커밋 완료' as note;
      t       |    note     
--------------+-------------
 05:52:24.426 | A 커밋 완료
(1 row)

--- 세션 B
[B] 다른 포장 완료: 원장 id5(-2) 즉시 커밋
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
      t       
--------------
 05:52:21.441
(1 row)

insert into inventory_tx(product_id, qty_delta) values (1,-2) returning id;
 id 
----
  5
(1 row)

--- 집계기
[집계 1회차] A 커밋 전 — 집계기가 보는 미집계 행과 UPDATE 결과
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
      t       
--------------
 05:52:21.516
(1 row)

select id, qty_delta from inventory_tx where product_id=1 and id > (select last_tx_id from stock_balance) order by id;
 id | qty_delta 
----+-----------
  5 |        -2
(1 row)

UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(qty_delta),0) FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(id) FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id)
 WHERE EXISTS (SELECT 1 FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id);
UPDATE 1
select qty, last_tx_id from stock_balance;
 qty | last_tx_id 
-----+------------
  91 |          5
(1 row)

[집계 2회차] A 커밋 후
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t;
      t       
--------------
 05:52:24.504
(1 row)

select id, qty_delta from inventory_tx where product_id=1 and id > (select last_tx_id from stock_balance) order by id;
 id | qty_delta 
----+-----------
(0 rows)

UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(qty_delta),0) FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(id) FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id)
 WHERE EXISTS (SELECT 1 FROM inventory_tx t WHERE t.product_id=b.product_id AND t.id > b.last_tx_id);
UPDATE 0
select qty, last_tx_id from stock_balance;
 qty | last_tx_id 
-----+------------
  91 |          5
(1 row)

=== 최종: 조회값 vs 원장 진실
select b.qty + coalesce((select sum(qty_delta) from inventory_tx t where t.product_id=1 and t.id > b.last_tx_id),0) as on_hand_read, 100 + (select sum(qty_delta) from inventory_tx where product_id=1) as ledger_truth from stock_balance b;
 on_hand_read | ledger_truth 
--------------+--------------
           91 |           90
(1 row)

select id, qty_delta, (id > (select last_tx_id from stock_balance)) as visible_to_reads from inventory_tx where id in (4,5) order by id;
 id | qty_delta | visible_to_reads 
----+-----------+------------------
  4 |        -1 | f
  5 |        -2 | f
(2 rows)

```

### 결과
원장 진실은 100 − 1 − 2 − 4 − 1 − 2 = 90인데 조회값은 91이다. 05:52:21 집계 1회차는 보이는 행이 id5뿐이라 `last_tx_id`를 5로 올렸다. 05:52:24 A가 커밋한 id4는 5보다 작아 미집계 조회(`id > last_tx_id`)에 잡히지 않고(0 rows), 집계 2회차는 `UPDATE 0`이다. id4의 −1은 스냅샷에도 차분에도 영원히 들어가지 않는다. 대조기의 REBUILD도 같은 커서 규칙이라 복구하지 못한다.

### 수정
`created_at`을 DB가 `clock_timestamp()`로 기록하고, 집계는 `created_at < statement_timestamp() − 60초`인 행 가운데 첫 "젊은" 행보다 작은 id까지만 접는다. 전제: 원장 쓰기 트랜잭션은 행을 넣은 뒤 60초 안에 커밋(포장 완료 약 1초). IT `StockBalanceCollectorSettleIT.커밋_순서가_뒤바뀐_원장_행도_빠지지_않는다`를 정착 창 0으로 돌리면 `Expecting actual: 2L to be less than: 1L`로 같은 결함이 재현되고, 창 5초에서 통과한다.
