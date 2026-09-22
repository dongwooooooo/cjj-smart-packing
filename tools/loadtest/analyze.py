"""시험 구간의 Prometheus 시계열을 뽑아 판독용 표를 만든다. 백엔드 EC2 의 9090 에 내 IP 에서 접근한다.

사용: python3 analyze.py --prom http://<backend-ip>:9090 --start '2026-09-22T09:00:00+09:00' --end '2026-09-22T09:08:00+09:00' [--step 30s] [--profile capture|import|packing]
출력: 시각별 표(마크다운). k6 지연·실패율, 서버 p95, 촬영 구간 p95, Invoke p95, Hikari pending, executor queue, CPU, RDS 락 대기.
"""
import argparse, json, urllib.request, urllib.parse
from datetime import datetime

SERIES_CAPTURE = [
    ("VUs", "k6_vus", "{:.0f}"),
    ("k6 req/s", "sum(rate(k6_http_reqs_total[30s]))", "{:.1f}"),
    ("k6 p95(s)", "max(k6_http_req_duration_p95{name='measure'})", "{:.3f}"),
    ("k6 p99(s)", "max(k6_http_req_duration_p99{name='measure'})", "{:.3f}"),
    ("k6 max(s)", "max(k6_http_req_duration_max{name='measure'})", "{:.3f}"),
    ("k6 실패율", "max(k6_http_req_failed_rate{name='measure'})", "{:.3f}"),
    ("서버 p95(s)", "histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{uri='/api/v1/inbound/measurements'}[30s])))", "{:.3f}"),
    ("load p95", "histogram_quantile(0.95, sum by (le) (rate(measure_stage_seconds_bucket{stage='load'}[30s])))", "{:.3f}"),
    ("infer p95", "histogram_quantile(0.95, sum by (le) (rate(measure_stage_seconds_bucket{stage='infer'}[30s])))", "{:.3f}"),
    ("save p95", "histogram_quantile(0.95, sum by (le) (rate(measure_stage_seconds_bucket{stage='save'}[30s])))", "{:.3f}"),
    ("invoke p95", "histogram_quantile(0.95, sum by (le) (rate(inference_stage_seconds_bucket{stage='invoke'}[30s])))", "{:.3f}"),
    ("invoke p99", "histogram_quantile(0.99, sum by (le) (rate(inference_stage_seconds_bucket{stage='invoke'}[30s])))", "{:.3f}"),
    ("upload p95", "histogram_quantile(0.95, sum by (le) (rate(upload_duration_seconds_bucket[30s])))", "{:.3f}"),
    ("Hikari active", "hikaricp_connections_active", "{:.0f}"),
    ("Hikari pending", "hikaricp_connections_pending", "{:.0f}"),
    ("upload queue", "executor_queued_tasks{name='imageUploadExecutor'}", "{:.0f}"),
    ("CPU", "1 - avg(rate(node_cpu_seconds_total{mode='idle'}[30s]))", "{:.2f}"),
    ("heap", "sum(jvm_memory_used_bytes{area='heap'}) / sum(jvm_memory_max_bytes{area='heap'})", "{:.2f}"),
    ("RDS 연결", "sum(pg_stat_activity_count{datname='app'})", "{:.0f}"),
    ("RDS 락대기", "sum(pg_stat_activity_count{datname='app',wait_event_type='Lock'})", "{:.0f}"),
]

# 배치 접수(orders_import) 판독용. k6 import_duration 은 초 단위, orders 라벨은 배치 크기.
SERIES_IMPORT = [
    ("k6 batch/min", "sum(increase(k6_http_reqs_total{name='import'}[1m]))", "{:.1f}"),
    ("k6 p50(s)", "max(k6_import_duration_p50)", "{:.3f}"),
    ("k6 p95(s)", "max(k6_import_duration_p95)", "{:.3f}"),
    ("k6 max(s)", "max(k6_import_duration_max)", "{:.3f}"),
    ("주문당 p50(ms)", "max(k6_import_per_order_ms_p50) * 1000", "{:.2f}"),
    ("k6 실패율", "max(k6_http_req_failed_rate{name='import'})", "{:.3f}"),
    ("서버 p95(s)", "histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{uri='/api/v1/admin/orders/import'}[1m])))", "{:.3f}"),
    ("서버 max(s)", "max(http_server_requests_seconds_max{uri='/api/v1/admin/orders/import'})", "{:.3f}"),
    ("Hikari active", "hikaricp_connections_active", "{:.0f}"),
    ("Hikari pending", "hikaricp_connections_pending", "{:.0f}"),
    ("CPU", "1 - avg(rate(node_cpu_seconds_total{mode='idle'}[1m]))", "{:.2f}"),
    ("heap", "sum(jvm_memory_used_bytes{area='heap'}) / sum(jvm_memory_max_bytes{area='heap'})", "{:.2f}"),
    ("RDS 연결", "sum(pg_stat_activity_count{datname='app'})", "{:.0f}"),
    ("RDS 락대기", "sum(pg_stat_activity_count{datname='app',wait_event_type='Lock'})", "{:.0f}"),
    ("RDS 활성", "sum(pg_stat_activity_count{datname='app',state='active'})", "{:.0f}"),
    ("DB 행 읽기/s", "sum(rate(pg_stat_database_tup_returned{datname='app'}[1m]))", "{:.0f}"),
    ("DB 행 삽입/s", "sum(rate(pg_stat_database_tup_inserted{datname='app'}[1m]))", "{:.0f}"),
    ("tote 인덱스 행/s", "sum(rate(pg_stat_user_tables_idx_tup_fetch{relname='tote'}[1m]))", "{:.0f}"),
    ("tote 조회/s", "sum(rate(pg_stat_user_tables_idx_scan{relname='tote'}[1m]))", "{:.1f}"),
]

# 동시 포장 완료(packing) 판독용. 완료 p95 500ms 기준, 박스 재고 행 락 대기.
SERIES_PACKING = [
    ("VUs", "k6_vus", "{:.0f}"),
    ("k6 req/s", "sum(rate(k6_http_reqs_total[30s]))", "{:.1f}"),
    ("완료 p50(s)", "max(k6_complete_duration_p50)", "{:.3f}"),
    ("완료 p95(s)", "max(k6_complete_duration_p95)", "{:.3f}"),
    ("완료 max(s)", "max(k6_complete_duration_max)", "{:.3f}"),
    ("스캔 p95(s)", "max(k6_http_req_duration_p95{name='tote-scan'})", "{:.3f}"),
    ("상세 p95(s)", "max(k6_http_req_duration_p95{name='shipment-detail'})", "{:.3f}"),
    ("k6 실패율", "max(k6_http_req_failed_rate)", "{:.3f}"),
    ("서버 완료 p95(s)", "histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{uri='/api/v1/shipments/{shipmentId}/complete'}[30s])))", "{:.3f}"),
    ("서버 완료 max(s)", "max(http_server_requests_seconds_max{uri='/api/v1/shipments/{shipmentId}/complete'})", "{:.3f}"),
    ("완료 5xx/s", "sum(rate(http_server_requests_seconds_count{uri='/api/v1/shipments/{shipmentId}/complete',status=~'5..'}[30s]))", "{:.2f}"),
    ("완료 4xx/s", "sum(rate(http_server_requests_seconds_count{uri='/api/v1/shipments/{shipmentId}/complete',status=~'4..'}[30s]))", "{:.2f}"),
    ("Tomcat busy", "tomcat_threads_busy_threads", "{:.0f}"),
    ("Hikari active", "hikaricp_connections_active", "{:.0f}"),
    ("Hikari pending", "hikaricp_connections_pending", "{:.0f}"),
    ("CPU", "1 - avg(rate(node_cpu_seconds_total{mode='idle'}[30s]))", "{:.2f}"),
    ("RDS 연결", "sum(pg_stat_activity_count{datname='app'})", "{:.0f}"),
    ("RDS 락대기", "sum(pg_stat_activity_count{datname='app',wait_event_type='Lock'})", "{:.0f}"),
    ("RDS 커밋/s", "sum(rate(pg_stat_database_xact_commit{datname='app'}[30s]))", "{:.1f}"),
    ("RDS 롤백/s", "sum(rate(pg_stat_database_xact_rollback{datname='app'}[30s]))", "{:.1f}"),
]
PROFILES = {"capture": SERIES_CAPTURE, "import": SERIES_IMPORT, "packing": SERIES_PACKING}

def query_range(prom, expr, start, end, step):
    q = urllib.parse.urlencode({"query": expr, "start": start, "end": end, "step": step})
    with urllib.request.urlopen(f"{prom}/api/v1/query_range?{q}", timeout=60) as r:
        data = json.load(r)["data"]["result"]
    return {float(t): float(v) for s in data for t, v in s["values"] if v not in ("NaN", "+Inf", "-Inf")}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prom", required=True); ap.add_argument("--start", required=True); ap.add_argument("--end", required=True)
    ap.add_argument("--step", default="30s"); ap.add_argument("--profile", default="capture", choices=sorted(PROFILES))
    a = ap.parse_args()
    start = datetime.fromisoformat(a.start).timestamp(); end = datetime.fromisoformat(a.end).timestamp()
    cols = [(name, query_range(a.prom, expr, start, end, a.step), fmt) for name, expr, fmt in PROFILES[a.profile]]
    ts = sorted(set(t for _, s, _ in cols for t in s))
    print("| 시각 | " + " | ".join(n for n, _, _ in cols) + " |")
    print("| --- | " + " | ".join("---:" for _ in cols) + " |")
    for t in ts:
        row = [datetime.fromtimestamp(t).strftime("%H:%M:%S")]
        for _, s, fmt in cols:
            row.append(fmt.format(s[t]) if t in s else "")
        print("| " + " | ".join(row) + " |")

if __name__ == "__main__":
    main()
