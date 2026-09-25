"""조건 하나의 판독 구간 지표를 모아 result.json 으로 저장하고, 화면용 한 줄을 출력한다.

출처는 넷이다. k6 요약(판독 구간만 담은 measured_* 지표), Prometheus(서버·HikariCP·Tomcat·EC2·RDS 세션),
PostgreSQL 대기 이벤트 1초 샘플(waits.csv), CloudWatch RDS CPU(boto3, 실패하면 비워 둔다).

사용: python3 collect.py --dir <cond-dir> --prom http://host:9090 --start <epoch> --end <epoch>
"""
import argparse
import csv
import json
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

COMPLETE = "/api/v1/shipments/{shipmentId}/complete"
SCAN = "/api/v1/totes/scan"
DETAIL = "/api/v1/shipments/{shipmentId}"
IMPORT = "/api/v1/admin/orders/import"
APP = "PostgreSQL JDBC Driver"


def prom_query(prom: str, expr: str, at: float):
    q = urllib.parse.urlencode({"query": expr, "time": at})
    with urllib.request.urlopen(f"{prom}/api/v1/query?{q}", timeout=60) as r:
        res = json.load(r)["data"]["result"]
    if not res:
        return None
    v = float(res[0]["value"][1])
    return None if v != v else v  # NaN → None


def server_metrics(prom: str, start: float, end: float) -> dict:
    w = f"{int(end - start)}s"

    def q(expr):
        return prom_query(prom, expr, end)

    def hq(metric, quant, sel=""):
        return q(f"histogram_quantile({quant}, sum by (le) (increase({metric}_bucket{sel}[{w}])))")

    def uri(u, extra=""):
        return f'{{uri="{u}"{extra}}}'

    m = {}
    for name, u in (("complete", COMPLETE), ("scan", SCAN), ("detail", DETAIL), ("import", IMPORT)):
        m[f"http_{name}_p50"] = hq("http_server_requests_seconds", 0.5, uri(u))
        m[f"http_{name}_p95"] = hq("http_server_requests_seconds", 0.95, uri(u))
        m[f"http_{name}_p99"] = hq("http_server_requests_seconds", 0.99, uri(u))
        m[f"http_{name}_count"] = q(f"sum(increase(http_server_requests_seconds_count{uri(u)}[{w}]))")
        fails = q(f'sum(increase(http_server_requests_seconds_count{uri(u, ",status=~\"5..\"")}[{w}]))')
        m[f"http_{name}_5xx"] = fails if fails is not None or m[f"http_{name}_count"] is None else 0.0
    for t in ("acquire", "usage"):
        base = f"hikaricp_connections_{t}_seconds"
        for quant in (0.5, 0.95, 0.99):
            m[f"{t}_p{int(quant * 100)}"] = hq(base, quant)
        m[f"{t}_mean"] = q(f"sum(increase({base}_sum[{w}])) / sum(increase({base}_count[{w}]))")
        m[f"{t}_max"] = q(f"max(max_over_time({base}_max[{w}]))")
        m[f"{t}_count"] = q(f"sum(increase({base}_count[{w}]))")
    m["hikari_timeouts"] = q(f"sum(increase(hikaricp_connections_timeout_total[{w}]))")
    m["hikari_active_max"] = q(f"max(max_over_time(hikaricp_connections_active[{w}]))")
    m["hikari_active_avg"] = q(f"avg(avg_over_time(hikaricp_connections_active[{w}]))")
    m["hikari_pending_max"] = q(f"max(max_over_time(hikaricp_connections_pending[{w}]))")
    m["hikari_pending_avg"] = q(f"avg(avg_over_time(hikaricp_connections_pending[{w}]))")
    m["hikari_max"] = q("max(hikaricp_connections_max)")
    m["tomcat_busy_max"] = q(f"max(max_over_time(tomcat_threads_busy_threads[{w}]))")
    m["tomcat_busy_avg"] = q(f"avg(avg_over_time(tomcat_threads_busy_threads[{w}]))")
    m["tomcat_threads_max"] = q("max(tomcat_threads_config_max_threads)")
    m["ec2_cpu_avg"] = q(f'1 - avg(rate(node_cpu_seconds_total{{mode="idle"}}[{w}]))')
    m["ec2_cpu_max"] = q(f'max_over_time((1 - avg(rate(node_cpu_seconds_total{{mode="idle"}}[15s])))[{w}:5s])')
    m["rds_conn_max"] = q(f'max_over_time(sum(pg_stat_activity_count{{datname="app"}})[{w}:5s])')
    m["rds_commits_per_s"] = q(f'sum(rate(pg_stat_database_xact_commit{{datname="app"}}[{w}]))')
    m["rds_rollbacks_per_s"] = q(f'sum(rate(pg_stat_database_xact_rollback{{datname="app"}}[{w}]))')
    m["pg_deadlocks"] = q(f'sum(increase(pg_stat_database_deadlocks{{datname="app"}}[{w}]))')
    return m


def k6_metrics(summary_path: Path, measure_s: float) -> dict:
    if not summary_path.exists():
        return {}
    met = json.loads(summary_path.read_text())["metrics"]

    def g(name, key):
        return met.get(name, {}).get(key)

    m = {}
    for name in ("measured_complete", "measured_scan", "measured_detail", "import_duration"):
        for key in ("p(50)", "p(95)", "p(99)", "max", "avg", "count"):
            v = g(name, key)
            if v is not None:
                m[f"k6_{name.replace('measured_', '')}_{key.strip('p()')}"] = v
    ok = g("measured_complete_ok", "count") or 0
    m["k6_complete_ok"] = ok
    m["tps"] = ok / measure_s if measure_s else None
    m["k6_reqs"] = g("measured_reqs", "count") or 0
    m["k6_req_fail"] = g("measured_req_fail", "count") or 0
    m["k6_fail_rate"] = m["k6_req_fail"] / m["k6_reqs"] if m["k6_reqs"] else None
    m["k6_exhausted"] = g("packing_exhausted", "count") or 0
    m["k6_vus_max"] = g("vus_max", "value") or g("vus_max", "max")
    return m


def wait_metrics(csv_path: Path, start: float, end: float) -> dict:
    """앱 세션 중 일하는 세션(active, idle in transaction)의 대기 이벤트 표본 수. 1초 1표본."""
    if not csv_path.exists():
        return {}
    busy = Counter()
    seconds = set()
    idle_max = Counter()
    for row in csv.reader(csv_path.open()):
        if len(row) != 6 or not row[0].isdigit():
            continue
        ts, app, state, wtype, wevent, n = int(row[0]), row[1], row[2], row[3], row[4], int(row[5])
        if not (start <= ts <= end) or app != APP:
            continue
        seconds.add(ts)
        if state == "active":
            busy[f"{wtype}:{wevent}" if wtype != "CPU" else "CPU"] += n
        elif state == "idle in transaction":
            busy["IdleInTx:app"] += n
        elif state == "idle":
            idle_max[ts] += n
    secs = max(len(seconds), 1)
    top = busy.most_common(5)
    return {
        "wait_samples_s": len(seconds),
        "db_busy_avg": sum(busy.values()) / secs,  # 평균 일하는 세션 수(AAS 에 해당)
        "wait_top": [{"event": e, "avg_sessions": c / secs, "samples": c} for e, c in top],
        "wait_all": {e: c for e, c in busy.items()},
        "db_idle_max": max(idle_max.values()) if idle_max else None,
    }


def rds_cpu(rds_id: str, region: str, start: float, end: float) -> dict:
    try:
        import boto3
        cw = boto3.client("cloudwatch", region_name=region)
        out = {}
        for metric, stat in (("CPUUtilization", "Average"), ("CPUUtilization", "Maximum"),
                             ("CPUCreditBalance", "Minimum"), ("DatabaseConnections", "Maximum")):
            r = cw.get_metric_statistics(
                Namespace="AWS/RDS", MetricName=metric, Statistics=[stat], Period=60,
                Dimensions=[{"Name": "DBInstanceIdentifier", "Value": rds_id}],
                StartTime=datetime.fromtimestamp(start, timezone.utc),
                EndTime=datetime.fromtimestamp(end, timezone.utc))
            pts = [p[stat] for p in r["Datapoints"]]
            key = f"rds_{metric}_{stat}".lower()
            if pts:
                out[key] = sum(pts) / len(pts) if stat == "Average" else (max(pts) if stat == "Maximum" else min(pts))
        return out
    except Exception as e:  # CloudWatch 는 보조 지표다. 없으면 표에서 비운다
        return {"rds_cloudwatch_error": str(e)[:200]}


def fmt_ms(v):
    return "-" if v is None else f"{v * 1000:.1f}"


def console_row(meta: dict, r: dict) -> str:
    top = r.get("wait_top") or []
    top_s = f"{top[0]['event']}({top[0]['avg_sessions']:.1f})" if top else "-"
    return (f"pool {meta['pool']:>3} | VU {meta['vus']:>4} | pacing {meta['pacing_ms']:>6} | "
            f"TPS {r.get('tps') or 0:7.1f} | Queue-ms p95 {fmt_ms(r.get('acquire_p95')):>7} | "
            f"Run-ms p95 {fmt_ms(r.get('usage_p95')):>7} | http p95 {fmt_ms(r.get('http_complete_p95')):>7} | "
            f"pending max {r.get('hikari_pending_max') or 0:4.0f} | top wait {top_s}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--prom", required=True)
    ap.add_argument("--start", type=float, required=True)
    ap.add_argument("--end", type=float, required=True)
    ap.add_argument("--rds-id", default="cjj-postgres")
    ap.add_argument("--region", default="ap-northeast-2")
    a = ap.parse_args()
    d = Path(a.dir)
    meta = json.loads((d / "meta.json").read_text())
    r = {"window": {"start": a.start, "end": a.end}}
    r.update(k6_metrics(d / "summary.json", a.end - a.start))
    r.update(server_metrics(a.prom, a.start, a.end))
    r.update(wait_metrics(d / "waits.csv", a.start, a.end))
    r.update(rds_cpu(a.rds_id, a.region, a.start, a.end))
    (d / "result.json").write_text(json.dumps({"meta": meta, "result": r}, ensure_ascii=False, indent=1))
    print(console_row(meta, r))


if __name__ == "__main__":
    main()
