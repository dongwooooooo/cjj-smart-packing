\echo '[K] 집계기 역할: 수정 후 SQL, 정착 창(초)' :settle
select pg_sleep_until(:'t0'::timestamptz + interval '0.7 s');
\echo '[집계 1회차] A 커밋 전, B 커밋 후'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '집계 1회차' as note;
select id, qty_delta, round(extract(epoch from statement_timestamp() - created_at)::numeric, 3) as age_s from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
-- 수정 후 집계기 ADVANCE (backend f87a37e StockBalanceCollector). 파라미터 ?::float8 두 개 = :settle
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id
                         AND t.id > b.last_tx_id AND t.id <= s.new_last),
       last_tx_id = s.new_last,
       computed_at = now()
  FROM (
    SELECT b2.product_id,
           (SELECT MAX(t.id) FROM inventory_tx t
             WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id
               AND t.created_at < statement_timestamp() - make_interval(secs => :settle::float8)
               AND t.id < COALESCE((SELECT MIN(y.id) FROM inventory_tx y
                                     WHERE y.product_id = b2.product_id AND y.id > b2.last_tx_id
                                       AND y.created_at >= statement_timestamp()
                                                           - make_interval(secs => :settle::float8)),
                                   9223372036854775807)) AS new_last
      FROM stock_balance b2
  ) s
 WHERE b.product_id = s.product_id AND s.new_last IS NOT NULL AND b.last_tx_id < s.new_last;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select pg_sleep_until(:'t0'::timestamptz + interval '3.7 s');
\echo '[집계 2회차] A 커밋 전, B 행 나이 약 3.2초'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '집계 2회차' as note;
select id, qty_delta, round(extract(epoch from statement_timestamp() - created_at)::numeric, 3) as age_s from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
-- 수정 후 집계기 ADVANCE (backend f87a37e StockBalanceCollector). 파라미터 ?::float8 두 개 = :settle
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id
                         AND t.id > b.last_tx_id AND t.id <= s.new_last),
       last_tx_id = s.new_last,
       computed_at = now()
  FROM (
    SELECT b2.product_id,
           (SELECT MAX(t.id) FROM inventory_tx t
             WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id
               AND t.created_at < statement_timestamp() - make_interval(secs => :settle::float8)
               AND t.id < COALESCE((SELECT MIN(y.id) FROM inventory_tx y
                                     WHERE y.product_id = b2.product_id AND y.id > b2.last_tx_id
                                       AND y.created_at >= statement_timestamp()
                                                           - make_interval(secs => :settle::float8)),
                                   9223372036854775807)) AS new_last
      FROM stock_balance b2
  ) s
 WHERE b.product_id = s.product_id AND s.new_last IS NOT NULL AND b.last_tx_id < s.new_last;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select pg_sleep_until(:'t0'::timestamptz + interval '6.0 s');
\echo '[집계 3회차] A 커밋 후, A 행 나이 약 6초·B 행 나이 약 5.5초'
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, '집계 3회차' as note;
select id, qty_delta, round(extract(epoch from statement_timestamp() - created_at)::numeric, 3) as age_s from inventory_tx where product_id = 1 and id > (select last_tx_id from stock_balance where product_id = 1) order by id;
-- 수정 후 집계기 ADVANCE (backend f87a37e StockBalanceCollector). 파라미터 ?::float8 두 개 = :settle
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id
                         AND t.id > b.last_tx_id AND t.id <= s.new_last),
       last_tx_id = s.new_last,
       computed_at = now()
  FROM (
    SELECT b2.product_id,
           (SELECT MAX(t.id) FROM inventory_tx t
             WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id
               AND t.created_at < statement_timestamp() - make_interval(secs => :settle::float8)
               AND t.id < COALESCE((SELECT MIN(y.id) FROM inventory_tx y
                                     WHERE y.product_id = b2.product_id AND y.id > b2.last_tx_id
                                       AND y.created_at >= statement_timestamp()
                                                           - make_interval(secs => :settle::float8)),
                                   9223372036854775807)) AS new_last
      FROM stock_balance b2
  ) s
 WHERE b.product_id = s.product_id AND s.new_last IS NOT NULL AND b.last_tx_id < s.new_last;
select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
