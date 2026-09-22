\echo '# 5,000주문 배치: 위치 500건 단위 주문당 평균 간격(ms)'
with o as (
  select id, created_at, row_number() over (order by id) pos,
         extract(epoch from created_at - lag(created_at) over (order by id))*1000 gap_ms
  from orders where batch_id='LT-1-0-1790072244165')
select ((pos-1)/500)*500 as from_pos, round(avg(gap_ms)::numeric,1) avg_ms, round(percentile_cont(0.5) within group (order by gap_ms)::numeric,1) p50_ms, round(max(gap_ms)::numeric,0) max_ms
from o where gap_ms is not null group by 1 order by 1;
\echo '# 1,000주문 배치 5건: 앞 100건 vs 뒤 100건 평균 간격(ms)'
with o as (
  select batch_id, created_at, row_number() over (partition by batch_id order by id) pos,
         extract(epoch from created_at - lag(created_at) over (partition by batch_id order by id))*1000 gap_ms
  from orders where batch_id in (select batch_id from orders where created_at between '2026-09-22 10:07' and '2026-09-22 10:14' group by 1 having count(*)=1000))
select batch_id,
  round(avg(gap_ms) filter (where pos between 2 and 101)::numeric,1) first100_ms,
  round(avg(gap_ms) filter (where pos between 901 and 1000)::numeric,1) last100_ms
from o group by 1 order by 1;
\echo '# 100주문 배치 17건: 주문당 평균 간격(ms) — 유휴 토트 수는 같음'
select round(avg(gap_ms)::numeric,1) avg_ms from (
  select extract(epoch from created_at - lag(created_at) over (partition by batch_id order by id))*1000 gap_ms
  from orders where created_at between '2026-09-22 09:58' and '2026-09-22 10:03' and batch_id like 'LT-%') g where gap_ms is not null;
