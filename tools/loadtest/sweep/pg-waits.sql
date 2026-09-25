-- 1초마다 앱 세션을 상태·대기 이벤트별로 센다(영상의 Top Wait Event 표에 대응). \watch 가 같은 쿼리를 반복한다.
-- 출력: epoch,application_name,state,wait_event_type,wait_event,count. 대기 이벤트가 없는 active 는 CPU 로 본다.
SELECT extract(epoch FROM clock_timestamp())::bigint AS ts,
       application_name, coalesce(state, '-') AS state,
       coalesce(wait_event_type, 'CPU') AS wait_type, coalesce(wait_event, 'CPU') AS wait_event,
       count(*) AS n
FROM pg_stat_activity
WHERE backend_type = 'client backend' AND datname = current_database() AND pid <> pg_backend_pid()
GROUP BY 1, 2, 3, 4, 5;
\watch 1
