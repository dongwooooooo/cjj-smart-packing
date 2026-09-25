-- 실험이 남긴 재고 원장 행(:cutoff 보다 큰 id 중 실험 묶음 배송단위의 포장 완료)을 지우고 스냅샷을 원장에서 다시 만든다.
-- 조건마다 원장 크기를 같게 두기 위해서다. 원복 없이 돌리면 원장이 조건마다 약 6만 행씩 늘어, 같은 설정의 포화
-- 처리량이 4시간 동안 113 → 55건/s 로 내려갔다(docs/evidence/pool-sizing/README.md 6절).
-- 실험 전용 DB 에서만 쓴다. 원장은 운영에서 지우지 않는 기록이다.
\set ON_ERROR_STOP on
BEGIN;
LOCK TABLE stock_balance IN EXCLUSIVE MODE;  -- 집계기·대조기가 이 사이 스냅샷을 고치지 못하게
DELETE FROM inventory_tx t
 USING shipment s JOIN orders o ON o.id = s.order_id
 WHERE t.id > :cutoff AND t.tx_type = 'OUTBOUND_PACKED' AND t.ref_type = 'SHIPMENT'
   AND t.ref_id = s.id AND o.receipt_no LIKE :'prefix' || '%';
-- 남은 원장은 모두 정착한 행이라 합계와 최대 id 로 스냅샷을 만든다(대조기 REBUILD 와 같은 결과).
UPDATE stock_balance b
   SET qty = COALESCE(x.qty, 0), last_tx_id = COALESCE(x.last_id, 0), computed_at = now()
  FROM (SELECT p.id AS product_id, SUM(t.qty_delta) AS qty, MAX(t.id) AS last_id
          FROM product p LEFT JOIN inventory_tx t ON t.product_id = p.id GROUP BY p.id) x
 WHERE b.product_id = x.product_id;
COMMIT;
VACUUM (FULL, ANALYZE) inventory_tx;
VACUUM (ANALYZE) stock_balance;
SELECT 'ledger_rows' AS k, count(*) AS n, max(id) AS max_id FROM inventory_tx;
