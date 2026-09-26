-- ADVANCE 수정 A/B 용 합성 원장. 상품 10~17 에 고르게 :n 행(qty ±1 번갈아, 잔고가 크게 바뀌지 않게), 시각은 지금부터
-- 과거로 1행당 10ms(전부 정착 창 60초 밖). 스냅샷은 상품 10~17 을 마지막 행까지 접은 상태, 1~9 는 (0,0) 그대로.
-- ref_type = 'SYNTH' 로 표시해 나중에 지운다(ledger-reset.sql 은 실험 묶음 배송단위 행만 지우므로 따로 지워야 한다).
\set ON_ERROR_STOP on
SELECT count(*) AS before_rows FROM inventory_tx;
BEGIN;
LOCK TABLE stock_balance IN EXCLUSIVE MODE;
INSERT INTO inventory_tx (product_id, tx_type, qty_delta, ref_type, ref_id, created_at)
SELECT 10 + (g % 8), 'ADJUST', CASE WHEN g % 2 = 0 THEN 1 ELSE -1 END, 'SYNTH', g,
       clock_timestamp() - interval '2 minutes' - ((:n - g) * interval '10 ms')
FROM generate_series(1, :n) g;
UPDATE stock_balance b
   SET qty = x.qty, last_tx_id = x.last_id, computed_at = now()
  FROM (SELECT product_id, SUM(qty_delta) AS qty, MAX(id) AS last_id FROM inventory_tx GROUP BY product_id) x
 WHERE b.product_id = x.product_id;
COMMIT;
VACUUM (ANALYZE) inventory_tx;
SELECT count(*) AS after_rows, pg_size_pretty(pg_total_relation_size('inventory_tx')) AS size FROM inventory_tx;
SELECT product_id, qty, last_tx_id FROM stock_balance ORDER BY product_id;
