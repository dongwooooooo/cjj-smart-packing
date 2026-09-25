-- 풀 크기 실험용 배송단위 묶음(주문번호 접두사 :prefix)을 포장 전 상태로 되돌린다. 조건마다 같은 데이터로 시작하기 위해서다.
-- 되돌리는 것: 배송단위 상태(PACKING/PACKED → TOTE_ASSIGNED), 처음 배정된 토트 할당(해제 취소), 토트 상태, 박스 재고.
-- 되돌리지 않는 것: 재고 원장(inventory_tx)과 스냅샷. 원장은 지우지 않는 기록이라 포장 완료 행이 조건마다 쌓인다.
-- 시연 리셋(POST /admin/demo/reset)은 박스 재고를 100 으로 되돌려 수천 건 포장에서 OUT_OF_STOCK 이 나므로 쓰지 않는다.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE fx ON COMMIT DROP AS
SELECT s.id AS shipment_id,
       (SELECT min(ta.id) FROM tote_assignment ta WHERE ta.shipment_id = s.id) AS assignment_id
FROM shipment s JOIN orders o ON o.id = s.order_id
WHERE o.receipt_no LIKE :'prefix' || '%';

-- 처음 할당 뒤에 생긴 할당이 있으면(정상 경로에서는 없음) 원복이 토트 유니크 제약에 걸리므로 멈춘다.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM tote_assignment ta JOIN fx ON fx.shipment_id = ta.shipment_id
             WHERE ta.id <> fx.assignment_id) THEN
    RAISE EXCEPTION 'fixture shipment has extra tote assignments';
  END IF;
END $$;

UPDATE tote_assignment ta SET released_at = NULL
FROM fx WHERE ta.id = fx.assignment_id AND ta.released_at IS NOT NULL;
UPDATE tote t SET status = 'ASSIGNED'
FROM tote_assignment ta JOIN fx ON ta.id = fx.assignment_id
WHERE t.id = ta.tote_id AND t.status <> 'ASSIGNED';
UPDATE shipment s SET status = 'TOTE_ASSIGNED', packed_at = NULL, final_box_id = NULL
FROM fx WHERE s.id = fx.shipment_id AND s.status <> 'TOTE_ASSIGNED';
UPDATE box_type SET stock_qty = :box_stock WHERE stock_qty <> :box_stock;
SELECT 'fixture' AS k, count(*) AS shipments FROM fx;
COMMIT;
-- 갱신으로 생긴 죽은 행을 조건마다 같은 수준으로 치운다.
VACUUM (ANALYZE) shipment, tote_assignment, tote, box_type;
SELECT s.status, count(*) FROM shipment s JOIN orders o ON o.id = s.order_id
WHERE o.receipt_no LIKE :'prefix' || '%' GROUP BY 1;
