-- 박스 행 전부를 잡고 :hold 초 동안 놓지 않는다. 그동안 포장 완료 트랜잭션은 박스 행 락을 기다리며 커넥션을 쥔다.
BEGIN;
SELECT extract(epoch FROM clock_timestamp())::bigint AS locked_at, count(*) FROM (SELECT id FROM box_type FOR UPDATE) x;
SELECT pg_sleep(:hold);
COMMIT;
SELECT extract(epoch FROM clock_timestamp())::bigint AS released_at;
