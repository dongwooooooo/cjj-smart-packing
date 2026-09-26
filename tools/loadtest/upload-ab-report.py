"""upload-ab.sh 결과를 A/C 나란히 표(tables.md)와 포폴용 그림 2장으로 모은다.

사용: python3 upload-ab-report.py --dir docs/evidence/upload-before-response
출력: <dir>/tables.md, <dir>/m2-response-p95.png, <dir>/m3-pending.png
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


def charts(root: Path, res: dict) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams["font.family"] = "AppleGothic"
    plt.rcParams["axes.unicode_minus"] = False
    colors = {"A": "#8a8f98", "C": "#2f6fdf"}

    # M2 응답 p95 나란히
    loads = sorted({int(n.split("-v")[1]) for n in res if n.startswith("m2-")})
    fig, ax = plt.subplots(figsize=(7, 4.2), dpi=150)
    width = 0.36
    for i, lab in enumerate(("A", "C")):
        vals = [res.get(f"m2-{lab}-v{v}", {}).get("k6", {}).get("p95") or 0 for v in loads]
        xs = [j + (i - 0.5) * width for j in range(len(loads))]
        bars = ax.bar(xs, vals, width, color=colors[lab],
                      label="A 커밋 뒤 비동기 업로드" if lab == "A" else "C 응답 전 병렬 업로드")
        for x, v in zip(xs, vals):
            ax.text(x, v + 8, f"{v:.0f}ms", ha="center", fontsize=9)
    ax.set_xticks(range(len(loads)), [f"작업자 {v}명 3분" for v in loads])
    ax.set_ylabel("촬영 응답 p95 (ms, k6)")
    ax.set_ylim(0, max(1, ax.get_ylim()[1]) * 1.3)
    ax.set_title("M2 촬영 응답 p95 — A vs C")
    ax.legend(loc="upper center", ncol=2, fontsize=8, frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(root / "m2-response-p95.png")
    plt.close(fig)

    # M3 재시작·kill 뒤 PENDING 잔존 나란히
    def grouped(ax, groups, series, title, ylabel, fname, note=None):
        width = 0.8 / len(series)
        top = 1
        for i, (lab, color, vals, texts) in enumerate(series):
            xs = [j + (i - (len(series) - 1) / 2) * width for j in range(len(groups))]
            ax.bar(xs, vals, width, color=color, label=lab)
            for x, v, t in zip(xs, vals, texts):
                ax.text(x, v, t, ha="center", va="bottom", fontsize=8)
            top = max(top, max(vals))
        ax.set_xticks(range(len(groups)), groups, fontsize=9)
        ax.set_ylim(0, top * 1.3 + 1)
        ax.set_ylabel(ylabel)
        ax.set_title(title)
        ax.legend(loc="upper right", fontsize=8, frameon=False)
        ax.spines[["top", "right"]].set_visible(False)
        if note:
            ax.text(0.0, -0.2, note, transform=ax.transAxes, fontsize=7.5, color="#555")
        ax.figure.tight_layout()
        ax.figure.savefig(root / fname)
        plt.close(ax.figure)

    def settled_pending(name):
        return images(res.get(name, {}), "db_settled").get("PENDING", 0)

    def fails(name):
        return (res.get(name, {}).get("k6", {}) or {}).get("not_inferred") or 0

    m3 = [("m3", "재시작(SIGTERM)\n작업자 10명"), ("m3k", "강제 종료(SIGKILL)\n작업자 30명")]
    names = {"m3": "m3-{}", "m3k": "m3k-{}-v30"}
    series = []
    for lab in ("A", "C"):
        vals = [settled_pending(names[k].format(lab)) for k, _ in m3]
        texts = [f"PENDING {v}장\n실패 응답 {fails(names[k].format(lab))}건" for (k, _), v in zip(m3, vals)]
        series.append(("A 커밋 뒤 비동기 업로드" if lab == "A" else "C 응답 전 병렬 업로드", colors[lab], vals, texts))
    fig, ax = plt.subplots(figsize=(7.5, 4.4), dpi=150)
    grouped(ax, [g for _, g in m3], series, "M3 부하 중 backend 재시작 — 60초 뒤 PENDING 사진",
            "PENDING 사진 (장)", "m3-pending.png",
            "실패 응답은 재기동 중 연결 실패(http_0). 재시작·강제 종료 모두 1회 시행")

    # M4 포화 — 응답 시점·정착 뒤 PENDING 과 응답 p95
    m4 = [("A", "m4-A", colors["A"]), ("C", "m4-C", colors["C"]), ("C6", "m4-C6", "#7aa6f0")]
    groups = ["종료 직후 PENDING", "120초 뒤 PENDING"]
    series = []
    for lab, name, color in m4:
        if name not in res:
            continue
        end_p = images(res[name], "db_at_end").get("PENDING", 0)
        set_p = settled_pending(name)
        p95 = res[name]["k6"]["p95"] or 0
        label = {"A": "A 비동기", "C": "C 병렬(코어 3)", "C6": "C 병렬(코어 6)"}[lab] + f" · p95 {p95:.0f}ms"
        series.append((label, color, [end_p, set_p], [f"{end_p}장", f"{set_p}장"]))
    fig, ax = plt.subplots(figsize=(7.5, 4.4), dpi=150)
    grouped(ax, groups, series, "M4 작업자 60명 3분 — 보관소에 없는 사진",
            "PENDING 사진 (장)", "m4-pending.png")


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
    charts(root, res)
    print((root / "tables.md").read_text())


if __name__ == "__main__":
    main()
