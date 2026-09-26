"""upload-ab.sh 조건 디렉터리 하나를 한 줄 요약과 result.json 으로 모은다.

사용: python3 upload-ab-summary.py --dir docs/evidence/upload-before-response/m2-A-v10
"""
import argparse
import json
import re
from collections import Counter
from pathlib import Path


def read_json(path: Path):
    return json.loads(path.read_text()) if path.exists() else {}


def read_counts(path: Path) -> dict:
    """db_counts 결과(kind,status,count) → {"image": {"STORED": n}, "session": {...}, ...}"""
    out: dict = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        parts = line.strip().split(",")
        if len(parts) == 3 and parts[2].isdigit():
            out.setdefault(parts[0], {})[parts[1]] = int(parts[2])
    return out


def k6_stats(summary: dict) -> dict:
    metrics = summary.get("metrics", {})
    trend = metrics.get("measure_duration", {})
    rate = metrics.get("measure_inferred", {})
    return {
        "p50": trend.get("med"), "p95": trend.get("p(95)"), "p99": trend.get("p(99)"), "max": trend.get("max"),
        "requests": (rate.get("passes") or 0) + (rate.get("fails") or 0),
        "inferred": rate.get("passes"), "not_inferred": rate.get("fails"),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    d = Path(ap.parse_args().dir)
    k6 = k6_stats(read_json(d / "summary.json"))
    log = (d / "k6.log").read_text(errors="replace") if (d / "k6.log").exists() else ""
    reasons = Counter(re.findall(r"not_inferred reason=(\S+?)\"?\s", log))
    end, settled = read_counts(d / "db-counts-at-end.csv"), read_counts(d / "db-counts-settled.csv")
    result = {
        "id": d.name, "meta": read_json(d / "meta.json"), "window": read_json(d / "window.json"),
        "k6": k6, "not_inferred_reasons": dict(reasons),
        "db_at_end": end, "db_settled": settled,
        "pool": read_json(d / "pool.json"), "log_counts": read_json(d / "log-counts.json"),
        "rds_credit_after": (d / "rds-credit-after.txt").read_text().strip() if (d / "rds-credit-after.txt").exists() else "",
        "restart_at": (d / "restart-at.txt").read_text().split() if (d / "restart-at.txt").exists() else [],
    }
    (d / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=1))

    def fmt(v):
        return "-" if v is None else f"{v:.0f}"

    img_end, img_set = end.get("image", {}), settled.get("image", {})
    pool = result["pool"]
    print(f"요청 {k6['requests']} (INFERRED 아님 {k6['not_inferred']} {dict(reasons) or ''}) "
          f"p50/p95/p99/max {fmt(k6['p50'])}/{fmt(k6['p95'])}/{fmt(k6['p99'])}/{fmt(k6['max'])}ms, "
          f"사진 종료 직후 {img_end or '{}'} → 정착 뒤 {img_set or '{}'}, "
          f"업로드 풀 활성 최대 {pool.get('active_max')} 큐 최대 {pool.get('queue_max')} "
          f"CallerRuns {pool.get('caller_runs')}, 로그 {result['log_counts']}, "
          f"RDS 크레딧 {result['meta'].get('rds_credit_before')}→{result['rds_credit_after']}")


if __name__ == "__main__":
    main()
