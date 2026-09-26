// 시나리오 1 — 동시 촬영. 작업자 N 명이 각자 입고 화면에서 상품을 스캔하고 촬영 버튼을 누른다.
// 서버: /inbound/scans → /inbound/measurements (사진 3장 읽기 → Lambda Invoke → 세션 커밋, S3 업로드는 이미지에 따라
// 커밋 뒤 비동기(A) 또는 추론과 병렬·응답 전(C)).
// 판정: 촬영 응답 p95 < 1,000ms (SLO), 실패율 < 1%. 병목 후보: Lambda 동시 실행, HikariCP 풀, 업로드 executor.
// 부하 모양: 기본은 MAX 까지 단계적으로 올린다(실행 1·2). VUS 를 주면 작업자 VUS 명을 DURATION 동안 고정한다
// (upload-before-response M2~M4).
import { sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { post, ok } from './lib.js';

const MAX = parseInt(__ENV.MAX || '20', 10);
const measureMs = new Trend('measure_duration', true);
const inferred = new Rate('measure_inferred');
// INFERRED 가 아닌 응답을 사유별로 센다: HTTP 오류는 http_<코드>(연결 실패는 http_0), 200 이면 failReason
const notInferred = new Counter('measure_not_inferred');

const VUS = parseInt(__ENV.VUS || '0', 10);
const constant = {
  executor: 'constant-vus',
  vus: Math.max(1, VUS),
  duration: __ENV.DURATION || '3m',
  gracefulStop: '30s',
};

export const options = {
  scenarios: {
    capture: VUS > 0 ? constant : {
      executor: 'ramping-vus',
      startVUs: 1,
      // MAX 로 최대 동시 작업자 수를 바꾼다(기본 20). 단계는 MAX 의 10/25/50/100% 로 같은 비율로 올린다.
      stages: [
        { duration: '1m', target: Math.max(1, Math.round(MAX * 0.10)) },
        { duration: '2m', target: Math.max(1, Math.round(MAX * 0.25)) },
        { duration: '2m', target: Math.max(1, Math.round(MAX * 0.50)) },
        { duration: '2m', target: MAX },
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
  const isInferred = r.status === 200 && r.json('status') === 'INFERRED';
  inferred.add(isInferred);
  if (!isInferred) {
    const reason = r.status === 200 ? (r.json('failReason') || 'UNKNOWN') : `http_${r.status}`;
    notInferred.add(1, { reason });
    console.warn(`not_inferred reason=${reason}`); // k6.log 에서 사유별로 센다(요약에는 태그별 값이 안 남는다)
  }
  sleep(1); // 작업자가 화면을 확인하는 시간
}
