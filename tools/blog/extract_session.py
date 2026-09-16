"""세션 기록(.jsonl)에서 user/assistant 텍스트만 마크다운으로 추출한다.

사용: python3 extract_session.py <session.jsonl> [out.md] [--min-chars N] [--grep 단어]
도구 호출·결과·시스템 리마인더는 제외한다. 결정 대화를 블로그 소재로 발췌할 때 쓴다.
"""
import json, re, sys
from pathlib import Path

SKIP = ("<system-reminder>", "<local-command-", "<task-notification>", "[Request interrupted")

def texts(content):
    if isinstance(content, str):
        return [content]
    out = []
    for part in content:
        if isinstance(part, dict) and part.get("type") == "text":
            out.append(part.get("text", ""))
    return out

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    src = Path(args[0]); dst = Path(args[1]) if len(args) > 1 else src.with_suffix(".md")
    min_chars = int(sys.argv[sys.argv.index("--min-chars") + 1]) if "--min-chars" in sys.argv else 20
    pat = re.compile(sys.argv[sys.argv.index("--grep") + 1]) if "--grep" in sys.argv else None
    lines = [f"# 세션 발췌 — {src.stem}\n"]
    n = 0
    for raw in src.open(encoding="utf-8"):
        try:
            d = json.loads(raw)
        except json.JSONDecodeError:
            continue
        role = d.get("type")
        if role not in ("user", "assistant"):
            continue
        msg = d.get("message", {})
        for t in texts(msg.get("content", "")):
            t = t.strip()
            if len(t) < min_chars or any(s in t for s in SKIP):
                continue
            if pat and not pat.search(t):
                continue
            ts = (d.get("timestamp") or "")[:16].replace("T", " ")
            lines.append(f"\n## {ts} {role}\n\n{t}\n")
            n += 1
    dst.write_text("\n".join(lines), encoding="utf-8")
    print(f"{n} messages -> {dst}")

if __name__ == "__main__":
    main()
