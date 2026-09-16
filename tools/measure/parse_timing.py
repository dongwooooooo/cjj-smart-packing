"""백엔드 docker 로그의 measure.timing / inference.timing / upload.timing 줄을 구간별 p50/p95/p99 로 집계한다.

사용: docker compose logs backend --no-log-prefix | python3 parse_timing.py [--since '2026-09-16 08:00'] > table.md
"""
import argparse, re, sys

LINE = re.compile(r"(measure|inference|upload)\.timing (.*)$")
KV = re.compile(r"(\w+)=(\S+)")

def pct(v, p):
    v = sorted(v); i = max(0, min(len(v) - 1, round(p / 100 * len(v) + 0.5) - 1)); return v[i]

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--since", default=None); a = ap.parse_args()
    stages = {}
    for raw in sys.stdin:
        if a.since and raw[:19] < a.since:
            continue
        m = LINE.search(raw)
        if not m:
            continue
        kind = m.group(1); kv = dict(KV.findall(m.group(2)))
        for k, v in kv.items():
            if k.endswith("Ms") and v.replace(".", "", 1).isdigit():
                stages.setdefault(f"{kind}.{k}", []).append(float(v))
    print("| 구간 | n | p50 | p95 | p99 | max |\n| :-: | :-: | :-: | :-: | :-: | :-: |")
    order = ["inference.buildMs", "inference.invokeMs", "inference.parseMs", "measure.loadMs", "measure.inferMs",
             "measure.saveMs", "measure.totalMs", "upload.uploadMs"]
    for k in order + [k for k in stages if k not in order]:
        if k in stages:
            v = stages[k]; print(f"| {k} | {len(v)} | {pct(v,50):.0f} | {pct(v,95):.0f} | {pct(v,99):.0f} | {max(v):.0f} |")

if __name__ == "__main__":
    main()
