"""Grafana 대시보드를 판독 구간으로 열어 PNG 로 저장한다. 익명 보기(Viewer)가 켜져 있어 로그인 없이 연다.

사용: python3 capture.py --url '<grafana d/... URL>' --out grafana.png [--width 1600] [--height 1800]
"""
import argparse

from playwright.sync_api import sync_playwright


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=1600)
    ap.add_argument("--height", type=int, default=1900)
    a = ap.parse_args()
    url = a.url + ("&" if "?" in a.url else "?") + "kiosk&theme=light"
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": a.width, "height": a.height})
        page.goto(url, wait_until="networkidle", timeout=60000)
        page.wait_for_timeout(4000)  # 패널 질의가 끝나 그래프가 그려질 때까지
        page.screenshot(path=a.out, full_page=True)
        browser.close()


if __name__ == "__main__":
    main()
