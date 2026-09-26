"""upload-ab.sh 조건 디렉터리에서 도구 화면을 뽑아 screens/ 에 둔다.

- <조건>-k6.txt / .png : k6 실행 종료 콘솔(배너·실행 정보·THRESHOLDS·TOTAL RESULTS) 원문
- <조건>-psql-*.txt / .png : 상태별 사진 행 수 psql 출력 원문(있을 때)
- <조건>-grafana-top.png : Grafana 캡처의 첫 줄(응답 p50/p95/p99 · PENDING · 업로드 풀)만 잘라 낸 것(있을 때)

사용: python3 upload-ab-screens.py --dir docs/evidence/upload-before-response/m4-A [--dir ...]
"""
import argparse
import json
from pathlib import Path

from playwright.sync_api import sync_playwright

import importlib.util

_spec = importlib.util.spec_from_file_location("term2png", Path(__file__).with_name("term2png.py"))
term2png = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(term2png)

GRAFANA_TOP_PX = 440  # 대시보드 첫 줄(높이 9칸) + 상단 조건 토글. 1600px 폭 캡처 기준


def k6_console(cond: Path) -> str | None:
    log = cond / "k6.log"
    if not log.exists():
        return None
    lines = log.read_text(errors="replace").splitlines()
    lines = [l for l in lines if not l.startswith("K6START=")]
    # 배너~시나리오 설명(첫 "running (" 앞) + 요약(█ THRESHOLDS 부터 끝)
    head_end = next((i for i, l in enumerate(lines) if l.startswith("running (")), len(lines))
    tail_start = next((i for i, l in enumerate(lines) if "█ THRESHOLDS" in l or "█ TOTAL RESULTS" in l), None)
    if tail_start is None:
        return None
    body = lines[:head_end] + ["", "  ... (진행 표시 줄 생략) ...", ""] + lines[tail_start:]
    # 실행 중에 찍힌 사유별 실패 경고는 요약 앞에 개수만 남긴다(원문 줄은 k6.log 에 있다)
    warns = [l for l in lines if "not_inferred reason=" in l]
    if warns:
        body.insert(head_end + 1, f"  ... console.warn not_inferred {len(warns)}줄(k6.log 참조) ...")
    meta = json.loads((cond / "window.json").read_text()) if (cond / "window.json").exists() else {}
    cmd = (f"$ k6 run --out experimental-prometheus-rw --tag run={cond.name} "
           f"-e VUS={meta.get('vus', '?')} -e DURATION={meta.get('duration', '3m')} k6/capture.js")
    return "\n".join([cmd] + body)


def crop_top(src: Path, dst: Path) -> None:
    from PIL import Image
    im = Image.open(src)
    im.crop((0, 0, im.width, min(GRAFANA_TOP_PX, im.height))).save(dst)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", action="append", required=True)
    a = ap.parse_args()
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1800, "height": 1200}, device_scale_factor=2)
        for d in map(Path, a.dir):
            screens = d.parent / "screens"
            screens.mkdir(exist_ok=True)
            text = k6_console(d)
            if text:
                (screens / f"{d.name}-k6.txt").write_text(text + "\n")
                term2png.render(text, screens / f"{d.name}-k6.png", "ubuntu@loadgen: ~/upload-ab — k6 run", 120, page)
            for psql in sorted(d.glob("psql-*.txt")):
                name = f"{d.name}-{psql.stem}"
                (screens / f"{name}.txt").write_text(psql.read_text())
                term2png.render(psql.read_text(), screens / f"{name}.png", "ubuntu@backend: psql (RDS)", 90, page)
            if (d / "grafana.png").exists():
                crop_top(d / "grafana.png", screens / f"{d.name}-grafana-top.png")
            print(d.name, sorted(x.name for x in screens.glob(f"{d.name}-*")))
        browser.close()


if __name__ == "__main__":
    main()
