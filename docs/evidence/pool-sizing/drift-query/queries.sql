\timing on
-- MISMATCHES (StockReconciler, 60s)
EXPLAIN (ANALYZE, BUFFERS, SUMMARY) SELECT b.product_id, b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived, COALESCE(SUM(t.qty_delta), 0) AS ledger_total FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id GROUP BY b.product_id, b.qty, b.last_tx_id HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) <> COALESCE(SUM(t.qty_delta), 0);
-- NEGATIVE (StockReconciler, 60s)
EXPLAIN (ANALYZE, BUFFERS, SUMMARY) SELECT COUNT(*) FROM v_stock_on_hand WHERE on_hand_qty < 0;
-- ADVANCE (StockBalanceCollector, 5s) — 롤백
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, SUMMARY) UPDATE stock_balance b SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t WHERE t.product_id = b.product_id AND t.id > b.last_tx_id AND t.id <= s.new_last), last_tx_id = s.new_last, computed_at = now() FROM (SELECT b2.product_id, (SELECT MAX(t.id) FROM inventory_tx t WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id AND t.created_at < statement_timestamp() - make_interval(secs => 60::float8) AND t.id < COALESCE((SELECT MIN(y.id) FROM inventory_tx y WHERE y.product_id = b2.product_id AND y.id > b2.last_tx_id AND y.created_at >= statement_timestamp() - make_interval(secs => 60::float8)), 9223372036854775807)) AS new_last FROM stock_balance b2) s WHERE b.product_id = s.product_id AND s.new_last IS NOT NULL AND b.last_tx_id < s.new_last;
ROLLBACK;
-- LAG (StockBalanceCollector, 5s)
EXPLAIN (ANALYZE, BUFFERS, SUMMARY) SELECT COUNT(*) AS rows, COALESCE(EXTRACT(EPOCH FROM (statement_timestamp()::timestamp - MIN(t.created_at))), 0)::bigint FROM inventory_tx t JOIN stock_balance b ON b.product_id = t.product_id WHERE t.id > b.last_tx_id;
