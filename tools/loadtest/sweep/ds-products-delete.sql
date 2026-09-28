-- ds-products.sql 되돌리기. 데이터셋 상품이 실린 주문·배송단위가 없을 때만 성공한다(FK).
\set ON_ERROR_STOP on
BEGIN;
LOCK TABLE stock_balance IN EXCLUSIVE MODE;
DELETE FROM inventory_tx WHERE ref_type = 'DS_PRODUCTS' OR product_id IN (SELECT id FROM product WHERE name LIKE 'DS %');
DELETE FROM stock_balance WHERE product_id IN (SELECT id FROM product WHERE name LIKE 'DS %');
DELETE FROM product WHERE name LIKE 'DS %';
COMMIT;
SELECT count(*) FROM product;
