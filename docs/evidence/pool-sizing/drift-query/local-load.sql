-- :n 행을 상품 10~17 에 고르게, 시각은 지금부터 과거로 1행당 10ms. 스냅샷은 상품 1~9 = (0,0), 10~17 = 정착 창(60초) 밖까지 접힌 상태.
TRUNCATE inventory_tx, stock_balance;
INSERT INTO inventory_tx (product_id, tx_type, qty_delta, ref_type, ref_id, created_at)
SELECT 10 + (g % 8), 'OUTBOUND_PACKED', -1 - (g % 3), 'SHIPMENT', g, clock_timestamp() - ((:n - g) * interval '10 ms')
FROM generate_series(1, :n) g;
INSERT INTO stock_balance SELECT id, 0, 0 FROM product WHERE id < 10;
INSERT INTO stock_balance SELECT product_id, SUM(qty_delta), MAX(id) FROM inventory_tx WHERE created_at < clock_timestamp() - interval '60 s' GROUP BY product_id;
VACUUM ANALYZE;
SELECT count(*) AS ledger_rows, pg_size_pretty(pg_total_relation_size('inventory_tx')) FROM inventory_tx;
