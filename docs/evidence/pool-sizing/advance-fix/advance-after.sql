BEGIN;
EXPLAIN (ANALYZE, BUFFERS, SUMMARY)
UPDATE stock_balance b
   SET qty = b.qty + (SELECT COALESCE(SUM(t.qty_delta), 0) FROM inventory_tx t
                       WHERE t.product_id = b.product_id AND t.id > b.last_tx_id AND t.id <= s.new_last),
       last_tx_id = s.new_last,
       computed_at = now()
  FROM (
    SELECT b2.product_id,
           (SELECT MAX(t.id) FILTER (WHERE t.created_at < statement_timestamp() - make_interval(secs => 60::float8)
                                       AND t.id < COALESCE(y.first_young, 9223372036854775807))
              FROM inventory_tx t
             WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id) AS new_last
      FROM stock_balance b2
      CROSS JOIN LATERAL (
        SELECT MIN(t.id) FILTER (WHERE t.created_at >= statement_timestamp() - make_interval(secs => 60::float8)) AS first_young
          FROM inventory_tx t
         WHERE t.product_id = b2.product_id AND t.id > b2.last_tx_id
      ) y
  ) s
 WHERE b.product_id = s.product_id AND s.new_last IS NOT NULL AND b.last_tx_id < s.new_last;
ROLLBACK;
