# 원장 기반 재고 — 검토가 잡은 결함의 재현 로그 (2026-09-25)

임시 PostgreSQL 18.6 컨테이너(psql)와 수정 전 커밋 워크트리에서 다시 돌려 남긴 실제 출력이다. 코드 검토가 지적한 결함이 이론이 아니라 실행 결과로 드러나는지 확인했다.

## 1. 계획의 CTE 집계 SQL — 동시 집계 이중 반영

스냅샷 (qty 100, last_tx_id 0), 원장 id1(−1)·id2(−2) 커밋 상태. 집계기 C1이 트랜잭션을 열어 CTE UPDATE로 id1·2를 접고 커밋을 4초 미룬다. 그사이 id3(−4)이 커밋되고, 집계기 C2가 같은 SQL을 실행해 C1의 행 락을 기다린다.

```
 qty | last_tx_id | correct_qty
-----+------------+-------------
  90 |          3 |          93
```

정답은 100 − 1 − 2 − 4 = 93인데 90이 남았다. C2의 CTE `d`(delta −7, max_id 3)는 문장 시작 시점에 계산됐고, C1 커밋 뒤 재검사에서 `b.last_tx_id(2) < d.max_id(3)`이 참이라 −7을 통째로 더해 id1·2가 두 번 반영됐다. 수정: 상관 서브쿼리 UPDATE(`SET qty = qty + (SELECT SUM … WHERE id > b.last_tx_id AND id <= new_last)`)로 재검사 때 최신 `last_tx_id` 기준 잔여분만 더한다.

## 2. 대조기 상품 단위 격리 (실패 로그 없음)

실행으로 잡은 결함이 아니라 코드 읽기로 잡았다. `reconcileOnce()`가 `@Transactional` 하나로 묶여 있어 한 상품의 REBUILD가 예외를 내면 앞서 복구한 상품까지 롤백되고 지표 갱신도 건너뛴다. 수정 뒤 Mockito 단위 테스트(`StockReconcilerTest`)가 상품 1의 REBUILD를 `DataAccessResourceFailureException`으로 실패시키고 상품 2가 복구되며 `mismatch` 게이지가 2인 것을 확인한다. 수정 전 코드에 대한 실패 실행은 없다.

## 3. 같은 멱등 키 동시 요청 — 500

수정 전 커밋 f94c4b4 워크트리에서 동시성 IT `같은_키_동시_요청은_한_건만_기록되고_전부_200이다`(8스레드, 같은 키·같은 본문)를 실행했다.

```
exit=1
   8  but was: 500
   7 org.springframework.dao.DataIntegrityViolationException: could not execute statement
        [ERROR: duplicate key value violates unique constraint "ux_inventory_tx_idem"
   7 (POST http://localhost:N/api/v1/admin/inventory/adjustments) 500
WARN --- [o-auto-1-exec-8] org.hibernate.orm.jdbc.error : ERROR: duplicate key value violates unique constraint "ux_inventory_tx_idem"
```

8건 중 7건이 500. 둘 다 `findByIdempotencyKey`를 빈 값으로 통과한 뒤 두 번째 INSERT가 부분 유니크 인덱스에 걸렸고, 핸들러가 `DataIntegrityViolationException`을 몰라 `INTERNAL_ERROR`로 냈다. 수정: `adjust`를 트랜잭션 밖(`NOT_SUPPORTED`)에서 돌려 유니크 위반 뒤 같은 키를 다시 읽어 `duplicated: true`로 답한다. 수정 후 같은 IT는 8건 전부 200, txId 1개, `duplicated:false` 1건.

## 4. id 커서 — id를 먼저 받고 늦게 커밋한 행 영구 누락 (최종 검토 C1)

스냅샷 (93, last 3). 트랜잭션 A가 id4(−1)를 INSERT하고 4초 뒤 커밋(포장 완료가 원장 행을 넣은 뒤 박스 행 락을 기다리는 상황). 그사이 B가 id5(−2)를 즉시 커밋. 정착 창이 없는 집계 SQL(보이는 행의 MAX(id)까지 접음)을 A 커밋 전에 한 번, 커밋 뒤에 한 번 실행.

```
-- A 커밋 전 집계: 보이는 행은 id5뿐
    qty | last_tx_id
   -----+------------
     91 |          5
-- A 커밋 뒤 다시 집계 → UPDATE 0
 on_hand_read | ledger_truth | last_tx_id
--------------+--------------+------------
           91 |           90 |          5
 id | qty_delta | counted_by_reads
----+-----------+------------------
  4 |        -1 | f
```

원장 합은 90인데 조회는 91이다. id4는 `last_tx_id(5)`보다 작아 스냅샷에도, `id > last_tx_id` 차분에도 영원히 들어가지 않는다. 대조기의 REBUILD도 같은 커서 규칙이라 복구하지 못한다. 수정: `created_at`을 DB가 `clock_timestamp()`로 기록하고, 집계는 `created_at < statement_timestamp() − 60초`인 행 가운데 첫 "젊은" 행보다 작은 id까지만 접는다. 전제는 원장 쓰기 트랜잭션이 행을 넣은 뒤 60초 안에 커밋하는 것(포장 완료 약 1초).

같은 결함을 IT로도 재현했다. `StockBalanceCollectorSettleIT.커밋_순서가_뒤바뀐_원장_행도_빠지지_않는다`를 정착 창 0으로 돌리면:

```
Expecting actual: 2L to be less than: 1L
```

`last_tx_id`가 아직 커밋되지 않은 id 1을 넘어 2로 전진한 것이다. 창 5초에서는 통과한다.
