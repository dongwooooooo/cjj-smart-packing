-- 합성 원장 행을 지우고 스냅샷을 원장에서 다시 만든다(ledger-reset.sql 과 같은 방식).
\set ON_ERROR_STOP on
BEGIN;
LOCK TABLE stock_balance IN EXCLUSIVE MODE;
DELETE FROM inventory_tx WHERE ref_type = 'SYNTH';
UPDATE stock_balance b
   SET qty = COALESCE(x.qty, 0), last_tx_id = COALESCE(x.last_id, 0), computed_at = now()
  FROM (SELECT p.id AS product_id, SUM(t.qty_delta) AS qty, MAX(t.id) AS last_id
          FROM product p LEFT JOIN inventory_tx t ON t.product_id = p.id GROUP BY p.id) x
 WHERE b.product_id = x.product_id;
COMMIT;
VACUUM (FULL, ANALYZE) inventory_tx;
SELECT count(*) AS rows_after_delete FROM inventory_tx;
