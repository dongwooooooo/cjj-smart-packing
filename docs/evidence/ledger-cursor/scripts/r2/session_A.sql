\echo '[A] 포장 완료(늦게 커밋): 원장 행 INSERT 뒤 박스 행 락 대기를 pg_sleep(4)로 흉내'
select pg_sleep_until(:'t0'::timestamptz);
begin;
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'A INSERT' as note;
insert into inventory_tx(product_id, tx_type, qty_delta) values (1,'OUTBOUND_PACKED',-1) returning id;
select pg_sleep(4);
commit;
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'A 커밋 완료' as note;
