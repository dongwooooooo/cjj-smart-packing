"""풀 스윕 실시간 콘솔. pool-sweep.sh 가 도는 동안 몇 초마다 Prometheus 를 읽어 터미널 한 화면을 다시 그린다.

화면: 위에 지금 조건(풀 크기·작업자·pacing·connectionTimeout·Tomcat·단계), 가운데 실시간 값(TPS, 커넥션 획득 p95 =
Queue-ms, 점유 p95 = Run-ms, 포장 완료 http p95, HikariCP active/pending, Tomcat busy, PostgreSQL 대기 이벤트 상위 3,
EC2·RDS CPU), 아래 끝난 조건의 결과 표(pool-sweep.sh 가 조건마다 console.txt 에 쌓는 한 줄).

녹화: --cast 로 asciinema v2 형식(.cast)을 직접 쓴다(asciinema 설치 없이 asciinema play/웹 플레이어로 재생).
      --frames 로 N 번째 화면마다 텍스트 프레임을 남긴다(term2png.py 로 PNG 로 바꾼다).

사용: python3 live_console.py --prom http://<backend>:9090 --dir docs/evidence/pool-sizing/<스윕> \\
        [--interval 2] [--cast console.cast] [--frames frames/ --frame-every 5] [--rds-id <id> --region ap-northeast-2]
끝: 스윕 디렉터리에 README.md(보고서)가 생기면 마지막 화면을 남기고 끝낸다. Ctrl-C 도 같다.
"""
import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

COMPLETE = "/api/v1/shipments/{shipmentId}/complete"
APP = "PostgreSQL JDBC Driver"
WIDTH = 118


class Prom:
    def __init__(self, base: str):
        self.base = base

    def query(self, expr: str):
        q = urllib.parse.urlencode({"query": expr})
        try:
            with urllib.request.urlopen(f"{self.base}/api/v1/query?{q}", timeout=5) as r:
                return json.load(r)["data"]["result"]
        except Exception:  # noqa: BLE001 — 한 번 못 읽으면 그 칸만 비운다
            return None

    def scalar(self, expr: str):
        res = self.query(expr)
        if not res:
            return None
        v = float(res[0]["value"][1])
        return None if v != v else v


class RdsCpu:
    """CloudWatch RDS CPUUtilization(1분 지표). 1분에 한 번만 부른다."""

    def __init__(self, rds_id: str | None, region: str):
        self.rds_id, self.region, self.value, self.at, self.fetched = rds_id, region, None, None, 0.0

    def get(self):
        if not self.rds_id or time.time() - self.fetched < 60:
            return self.value, self.at
        self.fetched = time.time()
        try:
            import boto3
            cw = boto3.client("cloudwatch", region_name=self.region)
            now = datetime.now(timezone.utc)
            r = cw.get_metric_statistics(Namespace="AWS/RDS", MetricName="CPUUtilization", Statistics=["Average"],
                                         Period=60, StartTime=now - timedelta(minutes=6), EndTime=now,
                                         Dimensions=[{"Name": "DBInstanceIdentifier", "Value": self.rds_id}])
            pts = sorted(r["Datapoints"], key=lambda p: p["Timestamp"])
            if pts:
                self.value, self.at = pts[-1]["Average"], pts[-1]["Timestamp"].astimezone().strftime("%H:%M")
        except Exception:  # noqa: BLE001
            pass
        return self.value, self.at


def current_condition(sweep: Path):
    """결과(result.json)가 아직 없는 가장 최근 조건 디렉터리."""
    metas = sorted(sweep.glob("*/meta.json"), key=lambda p: p.stat().st_mtime)
    for meta in reversed(metas):
        if not (meta.parent / "result.json").exists():
            return meta.parent, json.loads(meta.read_text())
    return None, None


LOAD_SEEN: dict[str, float] = {}  # 조건 id → 콘솔이 처음 k6 VU > 0 을 본 시각


def phase(meta: dict, vus):
    """k6 결과 파일은 부하 발생기에 있다가 조건이 끝나야 넘어오므로, 단계는 Prometheus 의 k6 VU 로 가른다."""
    cid = meta["id"]
    if not vus:
        if cid in LOAD_SEEN:
            return "집계 중 — 지표 수집·캡처"
        return "준비 — 설정 반영·재시작·원장/묶음 원복"
    start = LOAD_SEEN.setdefault(cid, time.time())
    el = int(time.time() - start)
    warm = meta.get("warmup_s", 30)
    if el < warm:
        return f"예열 {el:3d}/{warm}s (판독 제외)"
    return f"판독 {el - warm:3d}/{meta.get('measure_s')}s"


def fmt(v, spec="7.1f", none="      -"):
    return none if v is None else format(v, spec)


def live_values(p: Prom) -> dict:
    w = "15s"
    hq = lambda m, q: p.scalar(f"histogram_quantile({q}, sum by (le) (rate({m}_bucket[{w}]))) * 1000")  # noqa: E731
    v = {
        "tps": p.scalar(f'sum(rate(http_server_requests_seconds_count{{uri="{COMPLETE}",status=~"2.."}}[{w}]))'),
        "err": p.scalar(f'sum(rate(http_server_requests_seconds_count{{uri="{COMPLETE}",status=~"5.."}}[{w}]))'),
        "queue95": hq("hikaricp_connections_acquire_seconds", 0.95),
        "run95": hq("hikaricp_connections_usage_seconds", 0.95),
        "http95": p.scalar(f'histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{{uri="{COMPLETE}"}}[{w}]))) * 1000'),
        "active": p.scalar("sum(hikaricp_connections_active)"),
        "pending": p.scalar("sum(hikaricp_connections_pending)"),
        "pool": p.scalar("sum(hikaricp_connections_max)"),
        "busy": p.scalar("sum(tomcat_threads_busy_threads)"),
        "tomcat_max": p.scalar("sum(tomcat_threads_config_max_threads)"),
        "ec2": p.scalar('(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[15s]))) * 100'),
        # 끝난 조건의 k6 시계열이 5분 동안 남아 있어서, 최근 10초 안에 들어온 표본만 센다
        "k6_vus": p.scalar("sum(max_over_time(k6_vus[10s]))"),
    }
    waits = p.query(f'topk(3, sum by (wait_event_type, wait_event) (pg_stat_activity_count{{datname="app",'
                    f'application_name="{APP}",state="active"}}))') or []
    idle_tx = p.scalar(f'sum(pg_stat_activity_count{{datname="app",application_name="{APP}",state="idle in transaction"}})')
    top = [(f"{x['metric'].get('wait_event_type') or 'CPU'}:{x['metric'].get('wait_event') or 'CPU'}",
            float(x["value"][1])) for x in waits if float(x["value"][1]) > 0]
    if idle_tx:
        top.append(("IdleInTx:app", idle_tx))
    v["waits"] = sorted(top, key=lambda t: -t[1])[:3]
    return v


def bar(value, full, width=24):
    if value is None or not full:
        return " " * width
    n = max(0, min(width, round(value / full * width)))
    return "█" * n + "·" * (width - n)


def draw(sweep: Path, p: Prom, rds: RdsCpu, started: float) -> str:
    now = datetime.now().strftime("%H:%M:%S")
    cond, meta = current_condition(sweep)
    v = live_values(p)
    lines = [f" 커넥션 풀 스윕 — 실시간 콘솔   {sweep.name}   {now}   경과 {int(time.time() - started)}s",
             "═" * WIDTH]
    if meta:
        lines += [f" 조건  {meta['id']}",
                  f"   풀 크기 {meta['pool']:>3}   작업자(VU) {meta['vus']:>3}   pacing {meta['pacing_ms']}ms   "
                  f"connectionTimeout {meta['conn_timeout_ms']}ms   Tomcat {meta['tomcat_threads']}   반복 r{meta['rep']}",
                  f"   단계  {phase(meta, v['k6_vus'])}"]
    else:
        lines += [" 조건  (대기 — 다음 조건 준비 전이거나 스윕이 끝났다)", "", ""]
    cpu, cpu_at = rds.get()
    lines += ["─" * WIDTH,
              " 실시간 (최근 15초)",
              f"   처리량 TPS(포장 완료 2xx/s) {fmt(v['tps'])}   5xx/s {fmt(v['err'], '5.1f')}   k6 VU {fmt(v['k6_vus'], '4.0f')}",
              f"   Queue-ms p95 (커넥션 획득)   {fmt(v['queue95'], '8.1f')} ms",
              f"   Run-ms   p95 (커넥션 점유)   {fmt(v['run95'], '8.1f')} ms",
              f"   http p95 (포장 완료)        {fmt(v['http95'], '8.1f')} ms",
              f"   HikariCP active  {fmt(v['active'], '4.0f')} / {fmt(v['pool'], '3.0f', '  -')}  {bar(v['active'], v['pool'])}"
              f"   pending {fmt(v['pending'], '4.0f')}",
              f"   Tomcat   busy    {fmt(v['busy'], '4.0f')} / {fmt(v['tomcat_max'], '3.0f', '  -')}  {bar(v['busy'], v['tomcat_max'])}",
              "   PostgreSQL 대기 상위 3 (앱 세션 수)  " + ("   ".join(f"{k} {n:.0f}" for k, n in v["waits"]) or "-"),
              f"   CPU  EC2 {fmt(v['ec2'], '5.1f')}%   RDS {fmt(cpu, '5.1f')}% (CloudWatch 1분, {cpu_at or '-'})",
              "─" * WIDTH,
              " 결과 (조건이 끝날 때마다 쌓인다 — 판독 구간 평균·분위수)"]
    rows = (sweep / "console.txt").read_text().splitlines() if (sweep / "console.txt").exists() else []
    lines += [f"   {r}" for r in rows] or ["   (아직 없음)"]
    lines.append("═" * WIDTH)
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prom", required=True)
    ap.add_argument("--dir", required=True)
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--cast")
    ap.add_argument("--frames")
    ap.add_argument("--frame-every", type=int, default=5)
    ap.add_argument("--rds-id")
    ap.add_argument("--region", default="ap-northeast-2")
    ap.add_argument("--max-minutes", type=float, default=120)
    a = ap.parse_args()
    sweep = Path(a.dir)
    sweep.mkdir(parents=True, exist_ok=True)
    prom, rds = Prom(a.prom), RdsCpu(a.rds_id, a.region)
    frames = Path(a.frames) if a.frames else None
    if frames:
        frames.mkdir(parents=True, exist_ok=True)
    cast = open(a.cast, "w") if a.cast else None
    started = time.time()
    if cast:
        cast.write(json.dumps({"version": 2, "width": WIDTH + 2, "height": 40, "timestamp": int(started),
                               "title": f"pool sweep live console {sweep.name}"}) + "\n")
    tick, screen = 0, ""
    try:
        while True:
            screen = draw(sweep, prom, rds, started)
            out = "\x1b[H\x1b[2J" + screen + "\n"
            sys.stdout.write(out)
            sys.stdout.flush()
            if cast:
                cast.write(json.dumps([round(time.time() - started, 3), "o", out.replace("\n", "\r\n")]) + "\n")
                cast.flush()
            if frames and tick % a.frame_every == 0:
                (frames / f"frame-{tick:05d}.txt").write_text(screen + "\n")
            tick += 1
            if (sweep / "README.md").exists() or time.time() - started > a.max_minutes * 60:
                break
            time.sleep(a.interval)
    except KeyboardInterrupt:
        pass
    if frames:
        (frames / "final.txt").write_text(screen + "\n")
    if cast:
        cast.close()


if __name__ == "__main__":
    main()
