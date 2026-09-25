"""스윕 디렉터리의 조건별 result.json 을 모아 비교표 README.md 와 캡션 초안을 만든다.

사용: python3 report.py --dir docs/evidence/pool-sizing/<timestamp> [--grafana http://host:3000]
표의 수치는 판독 구간(워밍업 제외)만이다. 판정 초안은 PLAN.md 의 규칙을 기계적으로 적용한 것이라 사람이 확인한다.
"""
import argparse
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path

DASH = "cjj-pool-sizing"


def ms(v, digits=1):
    return "-" if v is None else f"{v * 1000:.{digits}f}"


def num(v, f="{:.0f}"):
    return "-" if v is None else f.format(v)


def pct(v):
    return "-" if v is None else f"{v * 100:.0f}%"


def grafana_url(base, r):
    w = r["result"]["window"]
    frm, to = int(w["start"] * 1000) - 30000, int(w["end"] * 1000) + 30000
    return f"{base}/d/{DASH}/?orgId=1&from={frm}&to={to}"


def tops(r, n=3):
    t = r["result"].get("wait_top") or []
    return ", ".join(f"{x['event']} {x['avg_sessions']:.1f}" for x in t[:n]) or "-"


def load_rows(root: Path, rds_id: str, region: str):
    """CloudWatch 1분 지표는 수집 직후 비어 있을 수 있다. 비어 있으면 여기서 다시 채워 result.json 에 쓴다."""
    import sys
    sys.path.insert(0, str(Path(__file__).parent))
    from collect import rds_cpu
    rows = []
    for p in sorted(root.glob("*/result.json")):
        r = json.loads(p.read_text())
        x = r["result"]
        if x.get("rds_cpuutilization_average") is None:
            x.pop("rds_cloudwatch_error", None)
            x.update(rds_cpu(rds_id, region, x["window"]["start"], x["window"]["end"]))
            p.write_text(json.dumps(r, ensure_ascii=False, indent=1))
        r["dir"] = p.parent.name
        rows.append(r)
    return rows


def main_table(rows, grafana):
    head = ("| 부하 | pool | timeout | threads | # | TPS(완료/s) | Queue-ms p95 / 평균 | Run-ms p95 / 평균 | "
            "완료 서버 p95 | 완료 k6 p95 / max | 스캔 k6 p95 | pending max | active max | Tomcat busy max | "
            "RDS CPU 평균 | EC2 CPU 평균 | DB 일하는 세션 평균 | 상위 대기(평균 세션) | 실패율 | 획득 타임아웃 | 그래프 |")
    out = [head, "|" + "|".join(["---"] * (head.count("|") - 1)) + "|"]
    for r in rows:
        m, x = r["meta"], r["result"]
        out.append("| " + " | ".join([
            m["load"] + (" **무효(묶음 소진)**" if x.get("k6_exhausted") else ""), str(m["pool"]), str(m["conn_timeout_ms"]), str(m["tomcat_threads"]), str(m["rep"]),
            num(x.get("tps"), "{:.1f}"),
            f"{ms(x.get('acquire_p95'), 2)} / {ms(x.get('acquire_mean'), 2)}",
            f"{ms(x.get('usage_p95'))} / {ms(x.get('usage_mean'))}",
            ms(x.get("http_complete_p95")),
            f"{num(x.get('k6_complete_95'))} / {num(x.get('k6_complete_max'))}",
            num(x.get("k6_scan_95")),
            num(x.get("hikari_pending_max")), num(x.get("hikari_active_max")), num(x.get("tomcat_busy_max")),
            num(x.get("rds_cpuutilization_average"), "{:.0f}%"), pct(x.get("ec2_cpu_avg")),
            num(x.get("db_busy_avg"), "{:.1f}"), tops(r),
            num(x.get("k6_fail_rate"), "{:.2%}"), num(x.get("hikari_timeouts")),
            f"[보기]({grafana_url(grafana, r)})",
        ]) + " |")
    return "\n".join(out)


def verdicts(rows):
    """PLAN.md 판정 규칙의 기계 적용. 부하 수준별로 풀 크기 순서대로 본다."""
    by = defaultdict(list)
    for r in rows:
        by[(r["meta"]["load"], r["meta"]["conn_timeout_ms"], r["meta"]["tomcat_threads"])].append(r)
    lines = []
    for key, rs in by.items():
        agg = defaultdict(list)
        for r in rs:
            agg[r["meta"]["pool"]].append(r["result"])
        pools = sorted(agg)

        def avg(pool, k):
            vs = [x.get(k) for x in agg[pool] if x.get(k) is not None]
            return sum(vs) / len(vs) if vs else None

        best = max(pools, key=lambda p: avg(p, "tps") or 0)
        best_tps = avg(best, "tps") or 0
        # 규칙 1: 최고 처리량의 98% 이상을 내는 가장 작은 풀
        r1 = next((p for p in pools if (avg(p, "tps") or 0) >= 0.98 * best_tps), None)
        # 규칙 2: 획득 대기 p95 가 1ms 이하가 되는 가장 작은 풀
        r2 = next((p for p in pools if (avg(p, "acquire_p95") or 1) <= 0.001), None)
        # 규칙 3: DB 쪽 일하는 세션 중 CPU 가 아닌 대기(Lock·LWLock·IO) 비율이 앞 크기보다 커지기 시작하는 풀
        def wait_share(p):
            tot = non = 0.0
            for x in agg[p]:
                for e, c in (x.get("wait_all") or {}).items():
                    tot += c
                    if e != "CPU" and not e.startswith("IdleInTx") and not e.startswith("Client"):
                        non += c
            return non / tot if tot else None
        shares = {p: wait_share(p) for p in pools}
        r3 = next((b for a, b in zip(pools, pools[1:])
                   if shares[a] is not None and shares[b] is not None and shares[b] > shares[a] + 0.05), None)
        lines.append(
            f"- **{key[0]}** (timeout {key[1]}ms, threads {key[2]}): 최고 TPS {best_tps:.1f}(pool {best}). "
            f"규칙1(최고 TPS 98% 이상 최소 풀) = {r1}, 규칙2(Queue-ms p95 ≤ 1ms 최소 풀) = {r2}, "
            f"규칙3(DB 대기 비중이 5%p 넘게 늘기 시작하는 풀) = {r3}. "
            f"DB 대기 비중: " + ", ".join(f"pool {p} {shares[p]:.0%}" if shares[p] is not None else f"pool {p} -"
                                          for p in pools))
    return "\n".join(lines)


def captions(rows):
    out = []
    for r in rows:
        m, x = r["meta"], r["result"]
        out.append(
            f"- `{r['dir']}`: 작업자 {m['vus']}명(사이클 {m['pacing_ms']}ms), 풀 {m['pool']}개. "
            f"포장 완료 {num(x.get('tps'), '{:.1f}')}건/s, 커넥션 획득 대기 p95 {ms(x.get('acquire_p95'), 2)}ms, "
            f"점유 p95 {ms(x.get('usage_p95'))}ms, 대기 줄(pending) 최대 {num(x.get('hikari_pending_max'))}. "
            f"DB 상위 대기: {tops(r, 2)}.")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--grafana", default="http://13.124.19.3:3000")
    ap.add_argument("--rds-id", default="cjj-postgres")
    ap.add_argument("--region", default="ap-northeast-2")
    a = ap.parse_args()
    root = Path(a.dir)
    rows = load_rows(root, a.rds_id, a.region)
    if not rows:
        raise SystemExit("result.json 이 없습니다")
    sweep = [json.loads(p.read_text()) for p in sorted(root.glob("sweep*.json"))]
    md = [f"# 풀 크기 스윕 결과 — {root.name}", "",
          f"생성: {datetime.now():%Y-%m-%d %H:%M}. 도구 `tools/loadtest/pool-sweep.sh`. 수치는 판독 구간(워밍업 제외)만.", ""]
    if sweep:
        md += ["## 실행 조건 (호출별)", "", "```json"] + [json.dumps(x, ensure_ascii=False) for x in sweep] + ["```", ""]
    md += ["## 조건별 비교표", "",
           "Queue-ms = HikariCP 커넥션 획득 시간(`hikaricp_connections_acquire`), Run-ms = 커넥션 점유 시간"
           "(`hikaricp_connections_usage`). 둘 다 서버 히스토그램 버킷에서 계산했다. 상위 대기는 1초 간격 "
           "`pg_stat_activity` 표본에서 active·idle in transaction 앱 세션을 대기 이벤트별로 센 평균 세션 수다.", "",
           main_table(rows, a.grafana), "",
           "## 판정 규칙 기계 적용 (초안, 사람이 확인)", "", verdicts(rows), "",
           "## 캡션 초안", "", captions(rows), ""]
    (root / "README.md").write_text("\n".join(md))
    print(f"작성: {root / 'README.md'}")


if __name__ == "__main__":
    main()
