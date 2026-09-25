-- 풀 크기 실험 묶음의 토트 바코드를 배송단위 id 순으로 뽑는다. k6 TOTES_FILE 의 원본.
SELECT t.barcode
FROM shipment s
JOIN orders o ON o.id = s.order_id
JOIN tote_assignment ta ON ta.shipment_id = s.id AND ta.released_at IS NULL
JOIN tote t ON t.id = ta.tote_id
WHERE o.receipt_no LIKE :'prefix' || '%'
ORDER BY s.id;
