"""upload-ab.sh 결과를 A/C 나란히 표(tables.md)로 모은다. 포폴 그림은 도구 화면(screens/)을 쓴다.

사용: python3 upload-ab-report.py --dir docs/evidence/upload-before-response
출력: <dir>/tables.md
"""
import argparse
import json
import re
from pathlib import Path

TIMING = re.compile(r"(measure|upload)\.timing (.*)$")
KV = re.compile(r"(\w+)=(\S+)")


def pct(values, p):
    """최근접 순위 백분위(parse_timing.py·measure_prod.py 와 같은 방식)."""
    v = sorted(values)
    if not v:
        return None
    i = max(0, min(len(v) - 1, round(p / 100 * len(v) + 0.5) - 1))
    return v[i]


def m1_rows(root: Path, label: str):
    dirs = sorted(d for d in root.glob(f"m1-{label}*") if d.is_dir())
    e2e, stages = [], {}
    for d in dirs:
        client = json.loads((d / "client.json").read_text())
        e2e += [s["e2eMs"] for s in client["samples"] if s["status"] == "INFERRED"]
        for line in (d / "backend.log").read_text(errors="replace").splitlines():
            m = TIMING.search(line)
            if not m:
                continue
            kv = dict(KV.findall(m.group(2)))
            for k, v in kv.items():
                if k.endswith("Ms") and v.isdigit():
                    stages.setdefault(f"{m.group(1)}.{k}", []).append(int(v))
    return [d.name for d in dirs], e2e, stages


def fmt(v):
    return "-" if v is None else f"{v:.0f}"


def m1_table(root: Path) -> str:
    out = ["### M1 단일 클라이언트 (11종 × 5회 × 2회차, ABBA 순서)", ""]
    data = {lab: m1_rows(root, lab) for lab in ("A", "C")}
    out.append("| 지표 | A p50 | A p95 | A p99 | A max | C p50 | C p95 | C p99 | C max |")
    out.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    keys = [("클라이언트 E2E", None), ("서버 total", "measure.totalMs"), ("사진 읽기 load", "measure.loadMs"),
            ("업로드 제출 submit", "measure.submitMs"), ("추론 infer", "measure.inferMs"),
            ("업로드 upload(C: 추론과 겹침, A: 응답 밖)", None), ("업로드 대기 upload.wait", "measure.uploadWaitMs"),
            ("저장 save", "measure.saveMs")]
    for name, key in keys:
        row = [name]
        for lab in ("A", "C"):
            _, e2e, st = data[lab]
            if name == "클라이언트 E2E":
                v = e2e
            elif name.startswith("업로드 upload"):
                v = st.get("measure.uploadMs") or st.get("upload.uploadMs") or []
            else:
                v = st.get(key, [])
            row += [fmt(pct(v, p)) if v else "-" for p in (50, 95, 99)] + [fmt(max(v)) if v else "-"]
        out.append("| " + " | ".join(row) + " |")
    na, nc = len(data["A"][1]), len(data["C"][1])
    out.append("")
    out.append(f"표본: A {na}건({', '.join(data['A'][0])}), C {nc}건({', '.join(data['C'][0])}). 단위 ms.")
    return "\n".join(out)


def load_results(root: Path):
    res = {}
    for f in sorted(root.glob("m[234]*-*/result.json")):
        res[f.parent.name] = json.loads(f.read_text())
    return res


def images(r, when):
    return r.get(when, {}).get("image", {})


def load_table(res: dict, prefix: str, title: str) -> str:
    rows = [f"### {title}", "",
            "| 조건 | 요청 | INFERRED 아님(사유) | p50 | p95 | p99 | max | 사진 종료 직후 | 사진 정착 뒤(M4 120초, 그 외 60초) | 사진 없는 세션 | 풀 활성·큐 최대 | CallerRuns | 거절 로그 | RDS 크레딧 전→후 |",
            "| --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- | ---: | ---: | --- |"]
    for name, r in res.items():
        if not name.startswith(prefix):
            continue
        k6 = r["k6"]
        noimg = r.get("db_settled", {}).get("session_without_image", {})
        pool = r.get("pool", {})
        rows.append("| " + " | ".join([
            name, str(k6["requests"]), f"{k6['not_inferred']} {r['not_inferred_reasons'] or ''}".strip(),
            fmt(k6["p50"]), fmt(k6["p95"]), fmt(k6["p99"]), fmt(k6["max"]),
            str(images(r, "db_at_end")), str(images(r, "db_settled")), str(noimg),
            f"{pool.get('active_max')} · {pool.get('queue_max')}", str(pool.get("caller_runs") or 0),
            str(r.get("log_counts", {}).get("rejected")),
            f"{r['meta'].get('rds_credit_before')}→{r.get('rds_credit_after')}"]) + " |")
    return "\n".join(rows)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    root = Path(ap.parse_args().dir)
    res = load_results(root)
    parts = [m1_table(root),
             load_table(res, "m2-", "M2 부하(작업자 10·30명, 3분)"),
             load_table(res, "m3-", "M3 부하(작업자 10명) 중 backend 재시작"),
             load_table(res, "m3k-", "M3 보조 — 부하 중 SIGKILL(크래시) 뒤 재기동"),
             load_table(res, "m4-", "M4 포화(작업자 60명, 3분)")]
    (root / "tables.md").write_text("\n\n".join(parts) + "\n")
    print((root / "tables.md").read_text())


if __name__ == "__main__":
    main()
