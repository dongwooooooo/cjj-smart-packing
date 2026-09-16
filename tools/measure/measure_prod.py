"""운영 백엔드(EC2·Lambda·S3)에 촬영 요청을 보내 클라이언트 E2E 를 잰다. 서버 구간은 docker 로그의
measure.timing / inference.timing / upload.timing 줄을 parse_timing.py 로 집계한다.

사용: python3 measure_prod.py --base http://<ip>:8000 --key <DEMO_API_KEY> --rounds 5 --out measure-prod.json
"""
import argparse, json, statistics, time, urllib.request
from pathlib import Path

def call(base, key, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method,
                                 headers={"Content-Type": "application/json", "X-Demo-Key": key})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())

def pct(v, p):
    v = sorted(v); i = max(0, min(len(v) - 1, round(p / 100 * len(v) + 0.5) - 1)); return v[i]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--key", required=True)
    ap.add_argument("--rounds", type=int, default=5); ap.add_argument("--out", default="measure-prod.json")
    ap.add_argument("--products", default=str(Path(__file__).resolve().parents[2] / "backend/demo/data/products.json"))
    a = ap.parse_args()
    prods = json.load(open(a.products))
    ids = []
    for p in prods:
        r = call(a.base, a.key, "POST", "/api/v1/inbound/scans", {"barcode": p["gtin"]})
        pid = (r.get("product") or {}).get("productId")
        if pid: ids.append((p["gtin"], pid))
    print("products:", len(ids))
    samples = []
    for rnd in range(a.rounds):
        for gtin, pid in ids:
            t0 = time.perf_counter()
            r = call(a.base, a.key, "POST", "/api/v1/inbound/measurements", {"productId": pid})
            ms = (time.perf_counter() - t0) * 1000
            samples.append({"round": rnd, "gtin": gtin, "status": r.get("status"), "e2eMs": round(ms, 1),
                            "sessionId": r.get("sessionId")})
    e2e = [s["e2eMs"] for s in samples if s["status"] == "INFERRED"]
    summary = {"n": len(e2e), "failed": len(samples) - len(e2e), "p50": pct(e2e, 50), "p95": pct(e2e, 95),
               "p99": pct(e2e, 99), "max": max(e2e), "mean": round(statistics.mean(e2e), 1)}
    print("client e2e (ms):", summary)
    json.dump({"summary": summary, "samples": samples}, open(a.out, "w"), indent=1)

if __name__ == "__main__":
    main()
