// 시나리오 3 — 동시 포장 완료. 포장 작업자 N 명이 토트를 스캔하고 포장 완료를 누른다.
// 서버: /admin/demo/outbound/next-tote → /totes/scan → /shipments/{id}/complete (재고 차감·박스 재고 락·토트 해제, 한 트랜잭션).
// 판정: 완료 p95, 실패율(OUT_OF_STOCK·INVALID_STATE 는 데이터 소진이지 결함이 아님 — 별도 집계), 박스 재고 행 락 대기.
import { sleep } from "k6";
import { SharedArray } from "k6/data";
import { Trend, Counter } from "k6/metrics";
import { post, get, ok } from "./lib.js";

// TOTES_FILE 이 있으면 DB 에서 미리 뽑은 [{barcode, shipmentId, lineId}] 를 작업자별로 나눠 쓴다.
// 시연용 피더(next-tote)는 호출마다 라인의 전체 대기 배송단위를 읽고, 작업자 둘이 같은 토트를 받을 수 있어
// 부하 시험에서는 측정 대상(스캔 → 상세 → 완료)을 가린다.
const TOTES = __ENV.TOTES_FILE
  ? new SharedArray("totes", () => JSON.parse(open(__ENV.TOTES_FILE)))
  : null;

const completeMs = new Trend("complete_duration", true);
const exhausted = new Counter("packing_exhausted");

export const options = {
  scenarios: {
    packers: {
      executor: "constant-vus",
      vus: parseInt(__ENV.VUS || "5", 10),
      duration: __ENV.DURATION || "3m",
    },
  },
  thresholds: { complete_duration: ["p(95)<500"] },
};

function nextBarcode() {
  if (TOTES) {
    const vus = parseInt(__ENV.VUS || "5", 10);
    const idx = __VU - 1 + __ITER * vus; // 작업자별로 겹치지 않는 토트
    return idx < TOTES.length ? TOTES[idx].barcode : null;
  }
  const lineId = 1 + ((__VU - 1) % 3);
  const next = post(
    `/api/v1/admin/demo/outbound/next-tote?lineId=${lineId}`,
    undefined,
    { name: "next-tote" },
  );
  return next.status === 204 ? null : next.json("barcode");
}

export default function () {
  const barcode = nextBarcode();
  if (!barcode) {
    exhausted.add(1);
    sleep(2);
    return;
  }
  const scan = post("/api/v1/totes/scan", { barcode }, { name: "tote-scan" });
  if (!ok(scan, "tote-scan")) {
    sleep(1);
    return;
  }
  const shipmentId =
    scan.json("shipmentId") || scan.json("shipment.shipmentId");
  const detail = get(`/api/v1/shipments/${shipmentId}`, {
    name: "shipment-detail",
  });
  const expected =
    detail.json("expectedWeightKg") || detail.json("weight.expectedKg") || 1.0;
  const done = post(
    `/api/v1/shipments/${shipmentId}/complete`,
    { measuredWeightKg: expected },
    { name: "complete" },
  );
  ok(done, "complete");
  completeMs.add(done.timings.duration);
  sleep(1);
}
