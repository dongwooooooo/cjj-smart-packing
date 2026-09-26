-- 2026-09-26 사고 후 합성 기준선. 데모 리셋으로 원장 20,317행(실험 전 기준선, 컷오프 id 21674)이 지워져
-- 되살릴 수 없어, 같은 행 수로 합성 원장을 넣는다. 이전 20,317행과 행 수만 같고 내용은 다르다.
-- 출고 상품 10~17 에 고르게(상품당 2,536행), qty −1·−2·−3 순환(상품당 약 −5,072)으로 잔고를 사고 전 수준
-- (약 9.4만~9.5만)에 맞춘다. 음수 잔고는 생기지 않는다. 시각은 2026-09-25 00:00 부터 1행당 10ms — 전부 정착 창 밖.
-- ref_type = 'SYNTH_BASELINE' 로 표시한다. ledger-reset.sql 은 컷오프보다 큰 id 만 지우므로 이 행은 남는다.
-- 한 번만 돌린다(두 번 돌리면 행이 두 배가 된다 — 처음에 이미 있으면 멈춘다).
\set ON_ERROR_STOP on
\set n 20288
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM inventory_tx WHERE ref_type = 'SYNTH_BASELINE') THEN
    RAISE EXCEPTION 'synthetic baseline already present';
  END IF;
END $$;
SELECT count(*) AS before_rows, max(id) AS before_max_id FROM inventory_tx;
BEGIN;
LOCK TABLE stock_balance IN EXCLUSIVE MODE;  -- 집계기·대조기가 이 사이 스냅샷을 고치지 못하게
INSERT INTO inventory_tx (product_id, tx_type, qty_delta, ref_type, ref_id, created_at, reason)
SELECT 10 + (g % 8), 'ADJUST', -1 - (g % 3), 'SYNTH_BASELINE', g,
       timestamp '2026-09-25 00:00:00' + g * interval '10 ms',
       '2026-09-26 사고 후 합성 기준선(풀 실험용)'
FROM generate_series(1, :n) g;
UPDATE stock_balance b
   SET qty = x.qty, last_tx_id = x.last_id, computed_at = now()
  FROM (SELECT product_id, SUM(qty_delta) AS qty, MAX(id) AS last_id FROM inventory_tx GROUP BY product_id) x
 WHERE b.product_id = x.product_id;
COMMIT;
VACUUM (ANALYZE) inventory_tx;
VACUUM (ANALYZE) stock_balance;
SELECT count(*) AS after_rows, max(id) AS after_max_id, pg_size_pretty(pg_total_relation_size('inventory_tx')) AS size FROM inventory_tx;
