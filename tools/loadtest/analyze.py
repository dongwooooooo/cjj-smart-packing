"""시험 구간의 Prometheus 시계열을 뽑아 판독용 표를 만든다. 백엔드 EC2 의 9090 에 내 IP 에서 접근한다.

사용: python3 analyze.py --prom http://<backend-ip>:9090 --start '2026-09-22T09:00:00+09:00' --end '2026-09-22T09:08:00+09:00' [--step 30s]
출력: 시각별 표(마크다운). k6 지연·실패율, 서버 p95, 촬영 구간 p95, Invoke p95, Hikari pending, executor queue, CPU, RDS 락 대기.
"""
import argparse, json, urllib.request, urllib.parse
from datetime import datetime

SERIES = [
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

def query_range(prom, expr, start, end, step):
    q = urllib.parse.urlencode({"query": expr, "start": start, "end": end, "step": step})
    with urllib.request.urlopen(f"{prom}/api/v1/query_range?{q}", timeout=60) as r:
        data = json.load(r)["data"]["result"]
    return {float(t): float(v) for s in data for t, v in s["values"] if v not in ("NaN", "+Inf", "-Inf")}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prom", required=True); ap.add_argument("--start", required=True); ap.add_argument("--end", required=True)
    ap.add_argument("--step", default="30s")
    a = ap.parse_args()
    start = datetime.fromisoformat(a.start).timestamp(); end = datetime.fromisoformat(a.end).timestamp()
    cols = [(name, query_range(a.prom, expr, start, end, a.step), fmt) for name, expr, fmt in SERIES]
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
