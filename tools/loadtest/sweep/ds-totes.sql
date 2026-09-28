-- 부하 측정용 토트 20,000개(바코드 DST-). 배송단위마다 토트가 하나씩 붙어, 상품 1,706종 묶음(DS-)을
-- 포화 3분 분량(약 3.4만 배송단위)으로 늘리려면 유휴 토트가 모자랐다. 토트 행은 상태만 오가고 다른 표를 건드리지 않는다.
INSERT INTO tote (barcode, status)
SELECT 'DST-' || LPAD(n::text, 5, '0'), 'IDLE'
  FROM generate_series(1, 20000) AS n
ON CONFLICT (barcode) DO NOTHING;
SELECT status, count(*) FROM tote GROUP BY 1 ORDER BY 1;
