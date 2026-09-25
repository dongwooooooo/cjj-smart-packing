select b.qty, b.last_tx_id, b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id > b.last_tx_id), 0) as on_hand_read, (select sum(qty_delta) from inventory_tx where product_id = 1) as ledger_truth from stock_balance b where b.product_id = 1;
select id, qty_delta, id > (select last_tx_id from stock_balance where product_id = 1) as visible_to_reads from inventory_tx where product_id = 1 and id in (4, 5) order by id;
-- 판별: 스냅샷 qty 와 커서(last_tx_id)까지의 원장 합이 다르면 커서 안쪽 행의 delta 가 스냅샷에 빠졌거나 두 번 들어갔다
select b.qty as snapshot_qty, b.last_tx_id, (select sum(t.qty_delta) from inventory_tx t where t.product_id = 1 and t.id <= b.last_tx_id) as ledger_sum_upto_cursor from stock_balance b where b.product_id = 1;
