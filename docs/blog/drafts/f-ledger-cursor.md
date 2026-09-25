# 원장 커서가 놓친 한 줄 — id 순서와 커밋 순서가 다를 때

> 초안 v1 (2026-09-25). 독자: 백엔드 개발자. 종결 `~다`. 근거: `docs/evidence/loadtest/ledger-review-repro.md`, 실행 5.

포장 완료가 상품 행을 잠그다 서로 기다리는 데드락을 없애려고 재고를 원장 방식으로 바꿨다. 잔고는 원장을 5초마다 접어 만든 스냅샷에 아직 접지 않은 행을 더해 읽는다. 이 글은 그 "접는 커서"가 정상 부하에서 원장 한 줄을 영원히 놓치는 결함을 코드 검토에서 발견하고, psql 세션 셋으로 재현하고, 정착 창을 두어 고치고, 같은 부하로 확인하기까지를 다룬다.

## 배경 — 원장, 스냅샷, 커서

재고는 두 테이블로 표현한다. `inventory_tx`는 입고·포장 차감·조정을 한 줄씩 쌓는 원장이고, `stock_balance`는 상품마다 `(qty, last_tx_id)` 한 행을 가진 스냅샷이다. 실재고는 다음 식으로 읽는다.

```
실재고 = stock_balance.qty + Σ inventory_tx.qty_delta (id > last_tx_id)
```

집계기는 5초마다 `id > last_tx_id`인 행을 상품별로 합쳐 `qty`에 더하고 `last_tx_id`를 그 행들의 최대 id로 올린다. 스냅샷은 성능을 위한 캐시일 뿐이고, 조회는 항상 미집계 행을 더하므로 집계가 늦어도 값은 정확하다 — 이것이 설계의 약속이었다.

포장 완료 트랜잭션은 이렇게 돈다. 품목마다 원장에 차감 행을 넣고(이때 id를 받는다), 박스 재고 행을 `FOR UPDATE`로 잠가 하나 빼고, 토트를 풀고, 커밋한다. 상품 행은 더 이상 잠그지 않는다.

## 문제 — 커서는 id로 움직이는데 커밋은 id 순서가 아니다

머지 전 최종 검토가 한 줄을 지적했다. "id를 먼저 받고 늦게 커밋한 행은 커서가 이미 지나간 뒤라 영원히 접히지 않는다."

포장 작업자 A가 상품 원장에 id 4를 넣고 박스 행 락 대기열에 선다. 작업자 B는 id 5를 넣고 락을 먼저 얻어 커밋한다. 이 순간 집계기가 돌면 보이는 행은 id 5뿐이고, 커서는 5가 된다. 뒤늦게 A가 커밋한 id 4는 `id > 5`가 아니므로 미집계 조회에도, 다음 집계에도 잡히지 않는다. 스냅샷에도 없고 차분에도 없으니 실재고에서 그 차감은 사라진다.

같은 박스를 쓰는 작업자 50명이 줄을 서면 커밋 순서는 락을 얻은 순서다. 부하 테스트에서 완료 한 건이 최대 999ms 기다렸고, 집계기는 5초마다 돈다. 매 주기마다 "원장 행은 넣었는데 아직 커밋 못 한" 완료가 있을 확률이 높다.

## 재현 — psql 세션 셋

PostgreSQL 18.6 컨테이너에 두 테이블만 만들고, 스냅샷을 `(93, last 3)`으로 둔 뒤 세 세션을 겹쳐 돌렸다. 세션 A는 포장 완료 1, 세션 B는 포장 완료 2, 나머지는 집계기다. 집계기 SQL은 수정 전 것이다.

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

세션별 출력을 시각 순으로 붙였다.

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

원장 합은 90인데 조회는 91이다. id 4의 −1은 어디에도 반영되지 않는다. 대조기의 재작성(REBUILD)도 같은 커서 규칙(`MAX(id)`)을 쓰므로 고치지 못한다. 캡션: `visible_to_reads = f`가 이 결함의 전부다 — 커밋된 행인데 조회 식이 보지 않는다.

## 원인 — 두 시점이 다르다

id는 INSERT 문이 실행되는 순간 시퀀스에서 나온다. 행이 남에게 보이는 시점은 커밋이다. 둘 사이에 락 대기 같은 시간이 끼면 순서가 뒤집힌다. `id > last_tx_id`라는 커서는 "id가 크면 나중 행"을 전제하는데, 그 전제가 커밋 순서에 대해서는 성립하지 않는다.

이 문제는 시퀀스 id를 증분 커서로 쓰는 모든 설계에 있다. 이벤트 테이블을 id로 폴링하는 아웃박스, 변경 로그를 마지막 id 이후로 읽는 동기화, 모두 같은 구멍이 있다.

## 수정 — 정착 창

커서를 올릴 때 "이 행보다 작은 id를 가진 미커밋 행이 없다"를 보장할 방법이 필요하다. 두 가지 후보를 놓고 골랐다.

| 방식 | 내용 | 판단 |
| --- | --- | --- |
| 정착 창 | 행이 들어온 지 W초가 지난 행까지만 접는다. 전제: 원장을 쓰는 트랜잭션은 행을 넣은 뒤 W초 안에 끝난다 | 채택. 스키마 변경이 작고 전제가 명확하다 |
| xid 커서 | 행에 `xid8`을 기록하고 `pg_snapshot_xmin` 이전 트랜잭션까지만 접는다 | 엄밀하지만 커서를 id에서 xid로 바꿔야 해 변경이 크다 |

정착 창은 세 가지 선택으로 구성된다.

1. **`created_at`은 DB가 `clock_timestamp()`로 기록한다.** 트랜잭션 시작 시각(`now()`)이 아니라 INSERT 순간이다. 트랜잭션 시작 기준이면 "일찍 시작해 늦게 넣고 빨리 커밋한 행"이 정착으로 잘못 판정된다.
2. **기준 시각은 `statement_timestamp()`.** 한 문장 안에서 고정이고, 스냅샷을 잡기 전 시각이라 판정이 보수적이다.
3. **첫 "젊은" 행보다 작은 id까지만 접는다.** 창을 지난 행이라도 그보다 작은 id에 창 안의 행이 있으면 멈춘다.

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

논증은 한 줄이다. 접는 마지막 행 X가 창 W보다 오래됐다면, X보다 작은 id를 받은 트랜잭션도 행을 넣은 지 W가 넘었고, 전제에 따라 이미 끝났다. 끝난 트랜잭션의 행은 이 문장의 스냅샷에 보인다.

창은 60초로 두었다. 포장 완료는 약 1초라 여유가 크다. 조회 식은 그대로 `id > last_tx_id`를 더하므로 창 때문에 값이 늦어지지 않는다. 늦어지는 것은 스냅샷뿐이고, 그만큼 차분 쿼리가 최근 60초 행을 더 읽는다.

## 검증

같은 세 세션을 수정 후 SQL(창 3초)로 돌렸다.

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

1회차는 `UPDATE 0`이다. 창 안의 행을 접지 않았고, 조회는 그 사이에도 98로 정확하다. A가 커밋한 뒤 창이 지나자 두 행이 한 번에 접혀 스냅샷 97 = 원장 97이 됐다.

통합 테스트로도 고정했다. `StockBalanceCollectorSettleIT`는 스레드 하나가 트랜잭션 안에서 행을 넣고 래치로 멈춘 채, 다른 행을 커밋하고 집계기를 부른다. 같은 테스트를 창 0으로 돌리면 옛 결함이 그대로 나온다.

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

`last_tx_id`가 아직 커밋되지 않은 id 1을 넘어 2로 갔다는 단언 실패다. 창 5초에서는 통과한다.

배포 뒤 같은 부하(포장 작업자 50명, 3분)로 확인했다. 완료 5,874건 전부 성공, 데드락 0. 실행이 끝난 뒤 원장의 포장 차감 합과 `PACKED` 배송단위 품목 합이 47,662로 같았고, 스냅샷+차분과 원장 전체 합의 불일치는 0이었다. 실행 중 미집계 행은 최대 7,134개(창 안의 행), `lag_seconds`는 60에 머물렀다.

## 남은 과제

- **전제를 강제하는 장치가 없다.** "원장 쓰기 트랜잭션은 60초 안에 끝난다"는 코드 밖의 약속이다. PostgreSQL 18의 `transaction_timeout`을 앱 롤에 걸면 전제가 설정이 된다. 전제가 깨지면 대조기가 60초마다 전체 합과 비교해 복구하지만, 그 사이 조회값은 틀린다.
- **서버를 2대로 늘리면 집계기 실행 조정이 필요하다.** 인스턴스마다 스케줄러를 두는 대신 ShedLock으로 한 번에 하나만 돌린다. 지금 SQL은 겹쳐도 이중 반영이 없지만, 그것은 2차 방어다.
- **커서를 xid로 바꾸는 안**은 창이라는 시간 가정 없이 같은 보장을 준다. 원장이 초당 수백 건을 넘기면 다시 검토한다.
