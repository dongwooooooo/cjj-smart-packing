// 시나리오 3 — 동시 포장 완료. 포장 작업자 N 명이 토트를 스캔하고 포장 완료를 누른다.
// 서버: /admin/demo/outbound/next-tote → /totes/scan → /shipments/{id}/complete (재고 차감·박스 재고 락·토트 해제, 한 트랜잭션).
// 판정: 완료 p95, 실패율(OUT_OF_STOCK·INVALID_STATE 는 데이터 소진이지 결함이 아님 — 별도 집계), 박스 재고 행 락 대기.
//
// 작업자 한 사이클 = 스캔 → 상세 → (포장 작업 THINK_MS) → 완료 → (SLEEP_AFTER_MS). PACING_MS 가 있으면
// 사이클 길이를 그 값에 맞춘다(모자라면 끝에서 기다림). 풀 크기 실험(pool-sweep.sh)은 WARMUP_S 이후의
// 요청만 measured_* 지표에 넣어, k6 요약이 곧 워밍업을 뺀 판독 구간의 값이 되게 한다.
import { sleep } from "k6";
import exec from "k6/execution";
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
// 판독 구간(WARMUP_S 이후)만 담는 지표
const mComplete = new Trend("measured_complete", true);
const mScan = new Trend("measured_scan", true);
const mDetail = new Trend("measured_detail", true);
const mOk = new Counter("measured_complete_ok");
const mFail = new Counter("measured_req_fail");
const mReqs = new Counter("measured_reqs");
const mTimeout = new Counter("measured_fail_timeout"); // 클라이언트 타임아웃(status 0)
const m5xx = new Counter("measured_fail_5xx");
const m4xx = new Counter("measured_fail_4xx");
// 락 주입 구간(LOCK_FROM_S ~ LOCK_TO_S, 시험 시작 기준 초)에 시작한 요청만 따로 담는다.
const LOCK_FROM_MS = parseFloat(__ENV.LOCK_FROM_S || "-1") * 1000;
const LOCK_TO_MS = parseFloat(__ENV.LOCK_TO_S || "-1") * 1000;
const lockTrends = {
  scan: new Trend("lockwin_scan", true),
  detail: new Trend("lockwin_detail", true),
  complete: new Trend("lockwin_complete", true),
};
const lockFail = {
  timeout: new Counter("lockwin_fail_timeout"),
  s5xx: new Counter("lockwin_fail_5xx"),
  ok: new Counter("lockwin_ok"),
};

const THINK_MS = parseInt(__ENV.THINK_MS || "0", 10);
const SLEEP_AFTER_MS = parseInt(__ENV.SLEEP_AFTER_MS || "1000", 10);
const PACING_MS = parseInt(__ENV.PACING_MS || "0", 10);
const WARMUP_MS = parseInt(__ENV.WARMUP_S || "0", 10) * 1000;
// 판독 구간 끝. 비우면 끝까지. 지속 시간이 끝난 뒤 gracefulStop 동안 마무리되는 반복은 빼야
// 처리량(건수 / 판독 초)이 부풀지 않는다.
const WINDOW_END_MS = __ENV.MEASURE_S ? WARMUP_MS + parseInt(__ENV.MEASURE_S, 10) * 1000 : Infinity;

function inWindow() {
  const t = exec.instance.currentTestRunDuration;
  return t >= WARMUP_MS && t < WINDOW_END_MS;
}

// 판독 구간이면 요청 하나를 기록한다. 실패는 상태 코드 기준(2xx 아님, 타임아웃은 status 0).
function record(trend, res, name, startedAt) {
  if (!inWindow()) return;
  trend.add(res.timings.duration);
  mReqs.add(1);
  const bad = res.status < 200 || res.status >= 300;
  if (bad) mFail.add(1, { status: String(res.status) });
  if (res.status === 0) mTimeout.add(1);
  else if (res.status >= 500) m5xx.add(1);
  else if (res.status >= 400) m4xx.add(1);
  // startedAt 은 요청을 보낸 시각(시험 시작 기준 ms). 락 구간에 시작한 요청만 따로 센다.
  if (LOCK_FROM_MS >= 0 && startedAt >= LOCK_FROM_MS && startedAt < LOCK_TO_MS) {
    lockTrends[name].add(res.timings.duration, { outcome: bad ? String(res.status) : "ok" });
    if (res.status === 0) lockFail.timeout.add(1);
    else if (res.status >= 500) lockFail.s5xx.add(1);
    else if (!bad) lockFail.ok.add(1);
  }
}

function now() {
  return exec.instance.currentTestRunDuration;
}

export const options = {
  scenarios: {
    packers: {
      executor: "constant-vus",
      vus: parseInt(__ENV.VUS || "5", 10),
      duration: __ENV.DURATION || "3m",
    },
  },
  thresholds: { complete_duration: ["p(95)<500"] },
  summaryTrendStats: ["avg", "p(50)", "p(95)", "p(99)", "max", "count"],
};

function nextBarcode() {
  if (TOTES) {
    const vus = parseInt(__ENV.VUS || "5", 10);
    const offset = parseInt(__ENV.OFFSET || "0", 10); // 앞 실행이 쓴 토트를 건너뛴다
    const idx = offset + (__VU - 1) + __ITER * vus; // 작업자별로 겹치지 않는 토트
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
  // 사이클을 맞출 때 모든 작업자가 같은 순간에 누르지 않도록 첫 사이클만 시작을 흩는다.
  // 사이클 시작 시각은 흩은 뒤에 잰다. 앞에서 재면 흩은 시간이 첫 사이클에 포함돼, 흩은 시간이 짧은
  // 작업자들이 모두 정확히 PACING_MS 에 첫 사이클을 끝내고 그 뒤로 같은 순간에 누른다(2026-09-25 발견).
  if (PACING_MS > 0 && __ITER === 0) sleep((Math.random() * PACING_MS) / 1000);
  const cycleStart = Date.now();
  const barcode = nextBarcode();
  if (!barcode) {
    exhausted.add(1);
    sleep(2);
    return;
  }
  let t0 = now();
  const scan = post("/api/v1/totes/scan", { barcode }, { name: "tote-scan" });
  record(mScan, scan, "scan", t0);
  if (!ok(scan, "tote-scan")) {
    sleep(1);
    return;
  }
  const shipmentId =
    scan.json("shipmentId") || scan.json("shipment.shipmentId");
  t0 = now();
  const detail = get(`/api/v1/shipments/${shipmentId}`, {
    name: "shipment-detail",
  });
  record(mDetail, detail, "detail", t0);
  // 상세를 못 받으면 작업자는 예상 무게를 모른 채 완료를 누르지 않는다. 이 사이클은 상세 실패로만 센다.
  // (전에는 무게 1.0kg 으로 완료를 보내 무게 검수 409 가 실패율에 섞였다, 2026-09-26 수정)
  if (!ok(detail, "shipment-detail")) {
    sleep(1);
    return;
  }
  const expected =
    detail.json("expectedWeightKg") || detail.json("weight.expectedKg") || 1.0;
  if (THINK_MS > 0) sleep(THINK_MS / 1000);
  t0 = now();
  const done = post(
    `/api/v1/shipments/${shipmentId}/complete`,
    { measuredWeightKg: expected },
    { name: "complete" },
  );
  if (ok(done, "complete") && inWindow()) mOk.add(1);
  completeMs.add(done.timings.duration);
  record(mComplete, done, "complete", t0);
  if (SLEEP_AFTER_MS > 0) sleep(SLEEP_AFTER_MS / 1000);
  if (PACING_MS > 0) {
    const left = PACING_MS - (Date.now() - cycleStart);
    if (left > 0) sleep(left / 1000);
  }
}
