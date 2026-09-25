"""풀 크기 실험용 출고지시를 고정 시드로 만들어 접수 API 로 넣는다. 한 번만 돌린다.

같은 시드면 주문 구성(품목 수·수량·지역)이 매번 같다. 주문번호는 FIXTURE_PREFIX 로 시작해
fixture-reset.sql 이 이 묶음만 골라 되돌린다.

사용: DEMO_KEY=... python3 make_fixture.py --base http://<backend>:8000 --orders 20000 [--batch 500] [--seed 7]
"""
import argparse
import json
import os
import random
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

REGIONS = ["SEOUL", "GYEONGGI", "BUSAN"]
CATALOG = json.loads((Path(__file__).parent.parent / "k6" / "outbound_catalog.json").read_text())


def make_batch(rng: random.Random, prefix: str, batch_no: int, size: int) -> dict:
    batch_id = f"{prefix}B{batch_no:04d}"
    orders = []
    for i in range(size):
        items = [{"gtin": rng.choice(CATALOG)["gtin"], "qty": 1 + rng.randrange(3)}
                 for _ in range(1 + rng.randrange(5))]
        orders.append({
            "receiptNo": f"{batch_id}-{i:04d}",
            "regionCode": rng.choice(REGIONS),
            "orderedAt": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
            "items": items,
        })
    return {"batchId": batch_id, "orders": orders}


def post(base: str, key: str, body: dict) -> tuple[int, str]:
    req = urllib.request.Request(
        f"{base}/api/v1/admin/orders/import", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "X-Demo-Key": key}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.status, r.read().decode()[:300]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--orders", type=int, required=True)
    ap.add_argument("--batch", type=int, default=500)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--prefix", default=os.environ.get("FIXTURE_PREFIX", "PSFIX-"))
    ap.add_argument("--start-batch", type=int, default=0, help="중단 후 재개할 배치 번호")
    a = ap.parse_args()
    key = os.environ.get("DEMO_KEY")
    if not key:
        sys.exit("DEMO_KEY 환경변수가 필요합니다")
    rng = random.Random(a.seed)
    batches = (a.orders + a.batch - 1) // a.batch
    for no in range(batches):
        body = make_batch(rng, a.prefix, no, min(a.batch, a.orders - no * a.batch))
        if no < a.start_batch:
            continue  # 난수 순서를 맞추려고 만들기만 하고 보내지 않는다
        t0 = time.time()
        status, text = post(a.base, key, body)
        print(f"batch {no + 1}/{batches} {body['batchId']} status={status} {time.time() - t0:.1f}s {text[:120]}",
              flush=True)
        if status >= 300:
            sys.exit(f"접수 실패: {status}")


if __name__ == "__main__":
    main()
