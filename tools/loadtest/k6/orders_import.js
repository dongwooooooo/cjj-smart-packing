// 시나리오 2 — 출고지시 배치 접수. 상위 시스템이 배치를 보내면 서버가 검증·편성·라인/토트 배정을 한 트랜잭션으로 처리한다.
// 배치 크기(주문 수)를 바꿔 가며 응답 시간과 편성 시간을 본다. 동시 배치는 ARRIVAL 로 조절.
// 판정: 배치 응답 시간이 주문 수에 선형인지, 동시 배치에서 커넥션·락 대기가 생기는지.
import { Trend } from 'k6/metrics';
import { post, ok } from './lib.js';

const importMs = new Trend('import_duration', true);
const perOrderMs = new Trend('import_per_order_ms', true);

const ORDERS = parseInt(__ENV.ORDERS || '100', 10);
const RATE = parseInt(__ENV.RATE || '1', 10);       // 분당 배치 수
const DURATION = __ENV.DURATION || '5m';

export const options = {
  scenarios: {
    batches: {
      executor: 'constant-arrival-rate',
      rate: RATE, timeUnit: '1m', duration: DURATION,
      preAllocatedVUs: 4, maxVUs: 8,
    },
  },
  thresholds: { 'http_req_failed{name:import}': ['rate<0.01'] },
};

const CATALOG = JSON.parse(open('./outbound_catalog.json')); // [{gtin, stockQty}] 치수 확정·재고 있는 상품
const REGIONS = ['SEOUL', 'GYEONGGI', 'BUSAN'];

function rnd(n) { return Math.floor(Math.random() * n); }

export default function () {
  const batchId = `LT-${__VU}-${__ITER}-${Date.now()}`;
  const orders = [];
  for (let i = 0; i < ORDERS; i++) {
    const lines = 1 + rnd(5);
    const items = [];
    for (let j = 0; j < lines; j++) {
      const p = CATALOG[rnd(CATALOG.length)];
      items.push({ gtin: p.gtin, qty: 1 + rnd(3) });
    }
    orders.push({ receiptNo: `${batchId}-${i}`, regionCode: REGIONS[rnd(REGIONS.length)],
      orderedAt: new Date().toISOString().slice(0, 19), items });
  }
  const r = post('/api/v1/admin/orders/import', { batchId, orders }, { name: 'import', orders: String(ORDERS) });
  ok(r, 'import');
  importMs.add(r.timings.duration, { orders: String(ORDERS) });
  perOrderMs.add(r.timings.duration / ORDERS, { orders: String(ORDERS) });
}
