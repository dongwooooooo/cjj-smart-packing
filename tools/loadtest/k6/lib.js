// 공통: 백엔드 주소·키, 판정 헬퍼. 부하 발생기 EC2 에서 실행한다.
//   BASE=http://172.31.64.6:8000 DEMO_KEY=... k6 run --out experimental-prometheus-rw <script>
import http from 'k6/http';
import { check } from 'k6';

export const BASE = __ENV.BASE || 'http://127.0.0.1:8000';
export const HEADERS = { 'Content-Type': 'application/json', 'X-Demo-Key': __ENV.DEMO_KEY || '' };

export function post(path, body, tags) {
  return http.post(`${BASE}${path}`, body === undefined ? null : JSON.stringify(body),
    { headers: HEADERS, tags, timeout: '60s' });
}

export function get(path, tags) {
  return http.get(`${BASE}${path}`, { headers: HEADERS, tags, timeout: '60s' });
}

export function ok(res, name) {
  return check(res, { [`${name} 2xx`]: r => r.status >= 200 && r.status < 300 });
}
