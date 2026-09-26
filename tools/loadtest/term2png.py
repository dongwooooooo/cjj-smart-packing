"""터미널 출력 텍스트를 터미널 화면 모양 PNG 로 찍는다(글자는 원문 그대로, 줄바꿈·공백 보존).

k6 요약·psql 출력·실시간 콘솔 프레임을 포폴에 "도구 화면" 으로 싣기 위해 쓴다. ANSI 색 코드는
지원하는 것(굵게·기본 8색)만 살리고 나머지는 지운다. 브라우저는 playwright(chromium).

사용: python3 term2png.py --in k6-summary.txt --out k6-summary.png [--title 'ubuntu@loadgen: k6 run'] [--cols 120]
"""
import argparse
import html
import re
from pathlib import Path

from playwright.sync_api import sync_playwright

ANSI = re.compile(r"\x1b\[([0-9;]*)m")
OTHER_ESC = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
COLORS = {30: "#5c6370", 31: "#e06c75", 32: "#98c379", 33: "#e5c07b", 34: "#61afef", 35: "#c678dd",
          36: "#56b6c2", 37: "#dcdfe4", 90: "#7f848e", 91: "#e06c75", 92: "#98c379", 93: "#e5c07b",
          94: "#61afef", 95: "#c678dd", 96: "#56b6c2", 97: "#ffffff"}


def ansi_to_html(text: str) -> str:
    out, open_span, pos = [], False, 0
    text = OTHER_ESC.sub("", text.replace("\r", ""))
    for m in ANSI.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        pos = m.end()
        codes = [int(c) for c in m.group(1).split(";") if c.isdigit()] or [0]
        if open_span:
            out.append("</span>")
            open_span = False
        style = []
        for c in codes:
            if c == 1:
                style.append("font-weight:700")
            elif c in COLORS:
                style.append(f"color:{COLORS[c]}")
        if style:
            out.append(f'<span style="{";".join(style)}">')
            open_span = True
    out.append(html.escape(text[pos:]))
    if open_span:
        out.append("</span>")
    return "".join(out)


PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
body{{margin:0;background:#1e1f22;padding:0}}
.win{{margin:0;background:#282c34;border-radius:8px;overflow:hidden;display:inline-block;min-width:{w}ch}}
.bar{{background:#3a3f4b;color:#abb2bf;font:13px -apple-system,'Apple SD Gothic Neo',sans-serif;padding:7px 12px}}
.dot{{display:inline-block;width:11px;height:11px;border-radius:50%;margin-right:6px;vertical-align:-1px}}
pre{{margin:0;padding:14px 16px;color:#dcdfe4;font:13px/1.35 'D2Coding','Menlo','Apple SD Gothic Neo',monospace;white-space:pre}}
</style></head><body><div class="win"><div class="bar"><span class="dot" style="background:#ff5f57"></span>
<span class="dot" style="background:#febc2e"></span><span class="dot" style="background:#28c840"></span>&nbsp;{title}</div>
<pre>{body}</pre></div></body></html>"""


def render(text: str, out: Path, title: str, cols: int, page=None) -> None:
    doc = PAGE.format(w=cols, title=html.escape(title), body=ansi_to_html(text.rstrip("\n")))
    page.set_content(doc)
    page.wait_for_timeout(100)
    page.locator(".win").screenshot(path=str(out))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--title", default="terminal")
    ap.add_argument("--cols", type=int, default=110)
    a = ap.parse_args()
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1800, "height": 1200}, device_scale_factor=2)
        render(Path(a.src).read_text(errors="replace"), Path(a.out), a.title, a.cols, page)
        browser.close()


if __name__ == "__main__":
    main()
