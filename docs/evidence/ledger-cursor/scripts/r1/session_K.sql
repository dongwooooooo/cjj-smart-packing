\echo '[K] 집계기·대조기 역할: 수정 전 SQL을 정해진 시점에 실행'
select pg_sleep_until(:'t0'::timestamptz + interval '0.7 s');
\echo '[집계 1회차] A1 커밋 전'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '집계 1회차' as note;
select id, qty_delta from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
-- 수정 전 집계기 ADVANCE (backend 4a63045~1 StockBalanceCollector)
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(t.id) FROM inventory_tx t
                      WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       computed_at = now()
 WHERE EXISTS (SELECT 1 FROM inventory_tx t
                WHERE t.product_id = b.product_id AND t.id > b.last_tx_id);
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select pg_sleep_until(:'t0'::timestamptz + interval '4.5 s');
\echo '[집계 2회차] A1 커밋 후'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '집계 2회차' as note;
select id, qty_delta from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
-- 수정 전 집계기 ADVANCE (backend 4a63045~1 StockBalanceCollector)
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(t.id) FROM inventory_tx t
                      WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       computed_at = now()
 WHERE EXISTS (SELECT 1 FROM inventory_tx t
                WHERE t.product_id = b.product_id AND t.id > b.last_tx_id);
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select pg_sleep_until(:'t0'::timestamptz + interval '5.0 s');
\echo '[대조 1회차] 미커밋 원장 행 없음'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '대조 1회차' as note;
-- 수정 전 대조기 MISMATCHES (backend 83dcf67 StockReconciler). 지표 inventory.reconcile.mismatch = 이 결과의 행 수
SELECT b.product_id,
       b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived,
       COALESCE(SUM(t.qty_delta), 0) AS ledger_total
  FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id
 GROUP BY b.product_id, b.qty, b.last_tx_id
HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0)
    <> COALESCE(SUM(t.qty_delta), 0);
-- 수정 전 대조기 REBUILD (backend 83dcf67 StockReconciler), 파라미터 ? 세 개 = product_id 1
UPDATE stock_balance
   SET qty = (SELECT COALESCE(SUM(qty_delta), 0) FROM inventory_tx WHERE product_id = 1),
       last_tx_id = (SELECT COALESCE(MAX(id), 0) FROM inventory_tx WHERE product_id = 1),
       computed_at = now()
 WHERE product_id = 1;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
-- 수정 전 대조기 MISMATCHES (backend 83dcf67 StockReconciler). 지표 inventory.reconcile.mismatch = 이 결과의 행 수
SELECT b.product_id,
       b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived,
       COALESCE(SUM(t.qty_delta), 0) AS ledger_total
  FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id
 GROUP BY b.product_id, b.qty, b.last_tx_id
HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0)
    <> COALESCE(SUM(t.qty_delta), 0);
select pg_sleep_until(:'t0'::timestamptz + interval '7.0 s');
\echo '[집계 3회차] A2 커밋 전, B2 커밋 후'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '집계 3회차' as note;
select id, qty_delta from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
-- 수정 전 집계기 ADVANCE (backend 4a63045~1 StockBalanceCollector)
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(t.id) FROM inventory_tx t
                      WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       computed_at = now()
 WHERE EXISTS (SELECT 1 FROM inventory_tx t
                WHERE t.product_id = b.product_id AND t.id > b.last_tx_id);
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select pg_sleep_until(:'t0'::timestamptz + interval '10.2 s');
\echo '[조회] A2 커밋 후'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'A2 커밋 후 조회' as note;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select pg_sleep_until(:'t0'::timestamptz + interval '11.2 s');
\echo '[대조 2회차] A3 커밋 전(미커밋 행 있음), B3 커밋 후'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '대조 2회차' as note;
-- 수정 전 대조기 MISMATCHES (backend 83dcf67 StockReconciler). 지표 inventory.reconcile.mismatch = 이 결과의 행 수
SELECT b.product_id,
       b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived,
       COALESCE(SUM(t.qty_delta), 0) AS ledger_total
  FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id
 GROUP BY b.product_id, b.qty, b.last_tx_id
HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0)
    <> COALESCE(SUM(t.qty_delta), 0);
-- 수정 전 대조기 REBUILD (backend 83dcf67 StockReconciler), 파라미터 ? 세 개 = product_id 1
UPDATE stock_balance
   SET qty = (SELECT COALESCE(SUM(qty_delta), 0) FROM inventory_tx WHERE product_id = 1),
       last_tx_id = (SELECT COALESCE(MAX(id), 0) FROM inventory_tx WHERE product_id = 1),
       computed_at = now()
 WHERE product_id = 1;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select pg_sleep_until(:'t0'::timestamptz + interval '15.0 s');
\echo '[조회·집계 4회차] A3 커밋 후'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '집계 4회차' as note;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
-- 수정 전 집계기 ADVANCE (backend 4a63045~1 StockBalanceCollector)
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       last_tx_id = (SELECT MAX(t.id) FROM inventory_tx t
                      WHERE t.product_id = b.product_id AND t.id > b.last_tx_id),
       computed_at = now()
 WHERE EXISTS (SELECT 1 FROM inventory_tx t
                WHERE t.product_id = b.product_id AND t.id > b.last_tx_id);
-- 수정 전 대조기 MISMATCHES (backend 83dcf67 StockReconciler). 지표 inventory.reconcile.mismatch = 이 결과의 행 수
SELECT b.product_id,
       b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived,
       COALESCE(SUM(t.qty_delta), 0) AS ledger_total
  FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id
 GROUP BY b.product_id, b.qty, b.last_tx_id
HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0)
    <> COALESCE(SUM(t.qty_delta), 0);
select pg_sleep_until(:'t0'::timestamptz + interval '15.5 s');
\echo '[대조 3회차] 미커밋 원장 행 없음'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '대조 3회차' as note;
-- 수정 전 대조기 MISMATCHES (backend 83dcf67 StockReconciler). 지표 inventory.reconcile.mismatch = 이 결과의 행 수
SELECT b.product_id,
       b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived,
       COALESCE(SUM(t.qty_delta), 0) AS ledger_total
  FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id
 GROUP BY b.product_id, b.qty, b.last_tx_id
HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0)
    <> COALESCE(SUM(t.qty_delta), 0);
-- 수정 전 대조기 REBUILD (backend 83dcf67 StockReconciler), 파라미터 ? 세 개 = product_id 1
UPDATE stock_balance
   SET qty = (SELECT COALESCE(SUM(qty_delta), 0) FROM inventory_tx WHERE product_id = 1),
       last_tx_id = (SELECT COALESCE(MAX(id), 0) FROM inventory_tx WHERE product_id = 1),
       computed_at = now()
 WHERE product_id = 1;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
-- 수정 전 대조기 MISMATCHES (backend 83dcf67 StockReconciler). 지표 inventory.reconcile.mismatch = 이 결과의 행 수
SELECT b.product_id,
       b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived,
       COALESCE(SUM(t.qty_delta), 0) AS ledger_total
  FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id
 GROUP BY b.product_id, b.qty, b.last_tx_id
HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0)
    <> COALESCE(SUM(t.qty_delta), 0);
