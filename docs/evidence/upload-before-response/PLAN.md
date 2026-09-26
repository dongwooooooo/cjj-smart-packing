# 촬영 사진 업로드 A/C 실측 계획 (2026-09-26)

설계안: `docs/superpowers/specs/2026-09-26-upload-before-response-design.md` 5절 M1~M4.

## 대상

| 조건 | 이미지 | 업로드 방식 |
| --- | --- | --- |
| A | `cj-ai-backend:latest` (cd6222eefbf2, backend main f87a37e) | 세션 커밋 뒤 비동기. 풀 코어 3 / 최대 6 / 큐 2,000, 차면 거절(AbortPolicy) |
| C | `cj-ai-backend:upload-c` (4d64567427fc, backend `feat/upload-before-response` a73311e) | 사진 로드 직후 3장 병렬 제출, 추론 뒤 join(상한 8초). 큐 200, 차면 요청 스레드가 직접 올림(CallerRuns) |

환경: EC2 백엔드 1대 + RDS + 실제 S3 + Lambda `live`. 부하·측정 클라이언트는 같은 VPC 의 부하 발생기 EC2(사설 IP). 조건마다 이미지 재생성 → 데모 리셋(추론 워밍 1회 포함). 부하 조건은 같은 작업자 수로 30초 예열한 뒤 3분을 잰다. 예열 구간의 세션·사진은 집계에서 뺀다(DB 시각 기준).

도구: `tools/loadtest/upload-ab.sh`(조건 실행), `tools/loadtest/upload-ab-summary.py`(요약), `tools/measure/measure_prod.py`(M1 클라이언트), `tools/measure/parse_timing.py`(서버 구간), k6 `capture.js`(VUS 고정 모드), Grafana `cjj-upload-ab` 대시보드.

## 측정과 판정

| # | 방법 | 기록 | 판정 |
| --- | --- | --- | --- |
| M1 | 11종 × 5회 순차(단일 클라이언트) | 서버 load/infer/save/upload/upload.wait/total, 클라이언트 E2E p50/p95/p99/max | C 의 E2E p50·p95 가 A 대비 +30ms 이내 |
| M2 | 작업자 10명·30명 각 3분 | 응답 p95·실패, 종료 직후·60초 뒤 `measurement_image` 상태별 건수, 업로드 풀 활성·큐 최대 | A: PENDING 잔존 여부. C: PENDING·FAILED 0 |
| M3 | 작업자 10명 부하 중 60초 시점 `docker compose restart backend` | 상태별 건수, 실패 응답 건수 | A: PENDING 잔존. C: 0 |
| M4 | 작업자 60명 3분(실행 2 재현) | A: 거절 로그·PENDING. C: 응답 p95 상승 폭·유실·CallerRuns | C 유실 0 |

## 측정 전 예측

근거: 운영 실측 2026-09-16(업로드 p50 109ms, 추론 p50 318ms), 부하 실행 2(2026-09-22, 작업자 45명·약 30 req/s 부터 A 업로드 큐 적체).

| # | 예측 | 근거 |
| --- | --- | --- |
| M1 | C 의 E2E p50·p95 는 A 대비 +30ms 이내. `upload.wait` p95 는 0~10ms | 업로드 109ms 가 추론 318ms 안에 끝난다 |
| M2 | A 10명: 종료 직후 PENDING 은 진행 중인 몇 장뿐, 60초 뒤 0. A 30명: 60초 뒤 PENDING 0(약 19 req/s 로 적체 시작점 30 req/s 아래). C 10·30명: PENDING·FAILED 0, p95 는 A 와 ±30ms | 작업자 1명 = 약 1.55초 주기(응답 0.55초 + 확인 1초) |
| M3 | A: 재시작 순간 대기 줄·진행 중 업로드가 끊겨 PENDING > 0 이 남는다. C: PENDING 0, 재시작 중 요청은 연결 실패로 끝난다 | 설계안 2절 |
| M4 | A: 약 39 req/s 로 큐가 초당 약 9건씩 자라 3분 뒤 약 1,600건(용량 2,000 미만이라 거절은 없을 수 있음), 종료 직후 PENDING 수천 장. C: 유실 0, 응답 p95 가 A 보다 오른다(업로드 풀 6스레드가 초당 약 117장을 소화해야 해 CallerRuns 발동 가능) | 실행 2 소화량 약 30 건/s |
