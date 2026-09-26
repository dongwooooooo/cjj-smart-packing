"""도구 캡처 여러 장을 나란히 붙인다(잘라 내기 선택). 각 장 위에 조건 이름 한 줄을 단다.

캡처 자체(그래프·수치)는 손대지 않는다. 조건 이름 줄만 덧붙인다.

사용: python3 stitch.py --out m2-p95.png --direction h \\
        'A 작업자 30명=m2-A-v30/grafana.png@0,60,800,365' 'C 작업자 30명=m2-C-v30/grafana.png@0,60,800,365'
"""
import argparse

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"


def load(spec: str):
    label, rest = spec.split("=", 1)
    path, _, box = rest.partition("@")
    im = Image.open(path).convert("RGB")
    if box:
        im = im.crop(tuple(int(v) for v in box.split(",")))
    return label, im


def labelled(label: str, im: Image.Image) -> Image.Image:
    font = ImageFont.truetype(FONT, 22)
    strip = 40
    out = Image.new("RGB", (im.width, im.height + strip), "white")
    ImageDraw.Draw(out).text((12, 8), label, fill="#111111", font=font)
    out.paste(im, (0, strip))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--direction", choices=["h", "v"], default="h")
    ap.add_argument("items", nargs="+")
    a = ap.parse_args()
    parts = [labelled(*load(s)) for s in a.items]
    gap = 12
    if a.direction == "h":
        w, h = sum(p.width for p in parts) + gap * (len(parts) - 1), max(p.height for p in parts)
    else:
        w, h = max(p.width for p in parts), sum(p.height for p in parts) + gap * (len(parts) - 1)
    canvas = Image.new("RGB", (w, h), "#e6e7ea")
    x = y = 0
    for p in parts:
        canvas.paste(p, (x, y))
        if a.direction == "h":
            x += p.width + gap
        else:
            y += p.height + gap
    canvas.save(a.out)


if __name__ == "__main__":
    main()
