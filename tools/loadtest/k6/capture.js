// 시나리오 1 — 동시 촬영. 작업자 N 명이 각자 입고 화면에서 상품을 스캔하고 촬영 버튼을 누른다.
// 서버: /inbound/scans → /inbound/measurements (사진 3장 읽기 → Lambda Invoke → 세션 커밋 → 비동기 S3 업로드).
// 판정: 촬영 응답 p95 < 1,000ms (SLO), 실패율 < 1%. 병목 후보: Lambda 동시 실행, HikariCP 풀, 업로드 executor.
import { sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { post, ok } from './lib.js';

const measureMs = new Trend('measure_duration', true);
const inferred = new Rate('measure_inferred');

export const options = {
  scenarios: {
    capture: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '1m', target: 2 },
        { duration: '2m', target: 5 },
        { duration: '2m', target: 10 },
        { duration: '2m', target: 20 },
        { duration: '1m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    'measure_duration': ['p(95)<1000'],
    'measure_inferred': ['rate>0.99'],
    'http_req_failed{name:measure}': ['rate<0.01'],
  },
};

const GTINS = JSON.parse(open('./gtins.json'));

export function setup() {
  // 상품 id 는 스캔 응답에서 얻는다. 리셋은 하지 않는다 — 테스트 중 데이터가 지워지면 안 된다.
  const ids = [];
  for (const g of GTINS) {
    const r = post('/api/v1/inbound/scans', { barcode: g }, { name: 'scan' });
    if (r.status === 200) ids.push(r.json('product.productId'));
  }
  if (ids.length === 0) throw new Error('scan 으로 productId 를 하나도 얻지 못했다');
  return { ids };
}

export default function (data) {
  const pid = data.ids[(__VU + __ITER) % data.ids.length];
  const r = post('/api/v1/inbound/measurements', { productId: pid }, { name: 'measure' });
  ok(r, 'measure');
  measureMs.add(r.timings.duration);
  inferred.add(r.status === 200 && r.json('status') === 'INFERRED');
  sleep(1); // 작업자가 화면을 확인하는 시간
}
