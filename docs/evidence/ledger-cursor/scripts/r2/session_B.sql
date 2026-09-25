\echo '[B] 포장 완료(바로 커밋): 원장 행 INSERT 즉시 커밋(autocommit)'
select pg_sleep_until(:'t0'::timestamptz + interval '0.5 s');
select to_char(clock_timestamp(),'HH24:MI:SS.MS') as t, 'B INSERT·커밋' as note;
insert into inventory_tx(product_id, tx_type, qty_delta) values (1,'OUTBOUND_PACKED',-2) returning id;
