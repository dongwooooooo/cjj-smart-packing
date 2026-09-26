# 포트폴리오 반영 후보 — 발생한 문제와 해결 목록 (2026-09-26)

문서(`docs/evidence`, `docs/blog/drafts`, `docs/superpowers`, `.superpowers/sdd`)와 git 이력(backend 206커밋, 포폴 101커밋, ai 33커밋)을 전수 조사해 합쳤다. 수치는 근거 문서·커밋 본문에 있는 값만 옮겼다. 등급은 포폴에서 차지할 자리 기준이다.

- 1등급: 사업 영향이 크고 전후 실측이 있어 "문제" 절 하나를 이룰 수 있는 항목
- 2등급: 1등급 안의 부품 문제. 테스트·재현 로그로 검증됨. 본문 문단이나 표 한 행
- 과제: 발견했으나 미해결. 정직하게 "남은 과제"로 실을 항목
- 방법: 결과가 아니라 검증 방법을 보여 주는 재료(테크블로그용)

근거 경로는 `/Users/idong-u/d/cjj-portfolio/` 기준.

## 1등급 — 문제 절 후보 (10건)

| # | 문제(사용자 관점) | 원인 | 해결 | 전후 수치 | 상태 | 근거 |
| --- | --- | --- | --- | --- | --- | --- |
| P1 | 포장 작업자 50명이 동시에 포장 완료를 누르면 40.4%가 실패하고, 락과 무관한 스캔·상세 조회까지 5초 넘게 멈춤 | 완료 트랜잭션이 상품 행을 `shipment_item` 순서로 `FOR UPDATE`. 배송단위마다 순서가 달라 순환 대기. 품목 5개 배송단위는 82.6% 실패 | 원장 기반 재고로 전환. 포장 완료는 `inventory_tx`에 행만 넣고 박스 행 하나만 잠금. 잔고는 5초 스냅샷에 미집계 차분을 더해 계산 | 실패 40.4%→0, p95 10.07초→73ms, 처리량 2.9→32.6건/s, 데드락 356→0, 재현 IT 20라운드 전부 실패→전부 통과 | main f87a37e | `docs/evidence/loadtest/README.md` 실행 4·5, `deadlock-repro-*.txt`, 스펙 `docs/superpowers/specs/2026-09-23-ledger-stock-design.md` |
| P2 | 원장 전환 후 코드 검토에서: 집계 커서가 늦게 커밋된 원장 행을 건너뛰어 조회 재고가 실제보다 많게 나옴 → 접수 배치가 없는 재고에 주문을 받음 | id 순서 ≠ 커밋 순서. 포장 완료가 원장 INSERT 뒤 박스 락을 기다림 | `created_at`을 `clock_timestamp()`로(V22), 정착 윈도우 60초 안의 첫 행 앞까지만 집계 | psql 재현 91/90 → 90/90, 가정 위반 비교군 91/90. IT 창 0 실패·창 5초 통과. 수정 전 대조기는 미커밋 행 없을 때만 복구(R1) | main, 글 F 완료 | `docs/evidence/ledger-cursor/README.md`, `docs/blog/drafts/f-ledger-cursor.md` |
| P3 | 4시간 실험 중 같은 조건 처리량이 113→66건/s(−41%), 무부하 RDS CPU 5→29% | 집계기 ADVANCE의 MAX/MIN 서브쿼리에 PostgreSQL MIN/MAX 인덱스 최적화가 걸려 기본 키를 id 순으로 훑음. 커서 0인 상품 9개는 매번 원장 전체 스캔(루프당 55.7만 행). 추정 행수 과대로 JIT 컴파일 248ms 추가 | `FILTER` 집계로 재작성해 `(product_id, id)` 인덱스로 커서 이후 행만 읽음. LAG는 LATERAL. `SET jit = off` | RDS 105만 행: 3,393ms→0.66ms, 버퍼 498,555→105, 무부하 CPU 26~30%→5~7%, 포화 처리량 84.9·42.9→117.3·118.0건/s | 브랜치 `fix/collector-advance-cost` 01d8107, 병합 전 | `docs/evidence/pool-sizing/advance-fix/README.md`, `drift-query/README.md` |
| P4 | 커넥션 풀 설정이 기본값. 실행 4에서 락 대기 트랜잭션이 커넥션 10개를 붙들어 무관한 요청이 획득 대기 최대 10.5초. 30초 상한은 작업자 화면(10초)이 포기한 요청을 서버가 20초 더 붙듦 | 풀 크기·타임아웃을 잰 적 없음 | 비즈니스 트래픽 산정(Little's law, 6개면 충분) → 부하 고정·풀만 변경 스윕 → 락 주입 실험 → 사전 규칙으로 결정 | 피크 1·3배: 풀 5~40 동일. 포화: 20까지 상승(125→137건/s), 30·40은 p95만 571ms→1.3초. 타임아웃 3초: 락 구간에서 화면보다 먼저 500, 포화 실패 0(획득 max 2.996초). 결정 풀 10·3초 | 브랜치 `feat/hikari-pool-sizing`, 병합 전. 글 G 완료 | `docs/evidence/pool-sizing/README.md`, `docs/blog/drafts/g-pool-sizing.md` |
| P5 | 박스 추천이 안 들어가는 박스를 추천(30³에 25×25×20 두 개). 무게를 넣자 요금 구간을 올리는 편성이 최적해 | 부피 비교(liquid cubing). 목적함수가 박스 수→부피뿐 | extreme point 적재 + FFD + 국소 탐색. 목적함수를 (총 요금, 박스 수, 부피) 사전식으로. 새 배송단위 이동 후보 추가. `OVERWEIGHT_ITEM`·`WEIGHT_MISMATCH` 검수 | 편성 테스트 21→39. 벤치마크 5,000주문 21.0초, 주문당 p95 13.8ms, 주문 50배에 주문당 1.16배. 벤치마크가 국소 탐색 NPE 발견→수정 | main | `docs/blog/drafts/b-cartonization.md`, `docs/evidence/benchmark/README.md`, `backend/docs/decisions-weight.md`, V13 |
| P6 | 촬영 응답 안에 S3 업로드 3회가 동기로 들어가 있고 그동안 커넥션 점유 | 트랜잭션 안 동기 업로드 | `AFTER_COMMIT` + `@Async` 전용 executor, 3회 재시도 후 `FAILED`(V20 `upload_status`) | 저장 p95 36→12ms, 백엔드 total p95 243→192ms(MinIO). 운영 E2E p95 796ms→실제 3뷰 611ms | main | `backend/docs/decisions-async-image-store.md`, `docs/evidence/measurement/prod-2026-09-16*.md` |
| P7 | 위 비동기화가 실패를 숨김: 작업자 100명 동시 촬영에서 응답 p95 0.54초·실패 0인데 사진 1,155장(385세션)이 PENDING으로 남음 | executor 큐 2,000 초과 시 거절이 로그 한 줄로 끝남. 재처리 경로 없음. 프로세스 재시작 시 큐 유실 | 없음(과제). Outbox+스케줄러 또는 CallerRuns 역압, 큐 알람 | 45명(30 req/s)부터 큐 적체, 18:18 2,000 도달 | 미해결. 사업 근거는 부하가 아니라 배포 재시작 유실 | `docs/evidence/loadtest/README.md` 실행 1·2 |
| P8 | 모델 정확도를 배포 전에 검사하지 않음. 학습 리포트 MAE 1.31cm vs 서빙 코드 재측정 2.06cm | 평가 프로토콜(분할·촬영 슬롯)이 달랐음 | 고정셋 2,024품목 게이트, 비열화 기준 + 절대 상한(3cm), 통과 시 alias 승격·기준선 승격 | INT8 정적 PTQ 1.48배 빠르지만 ±3cm 정답률 62.5%→22.6%로 차단(평균 MAE만 봤으면 통과). 게이트 첫 실행 통과, live→버전 5 | ai main | `docs/portfolio/section-full.md` 문제 3, `docs/evidence/eval/` |
| P9 | GPU 파드 전제의 8초 계약을 CPU Lambda로 옮기니 콜드스타트(초기화 최대 9.5초)가 계약을 넘김 | 비용 문제로 GPU 상시 점유 불가 | ONNX Runtime 전환(빌드 시 변환 + max diff 게이트), 시연 시간대 Provisioned Concurrency 예약, 리셋·배포 뒤 워밍 호출 | 추론 1,070→185ms, 로드 3.10→0.22초. 시연 기간 웜 246건 p50 325/p95 609ms, 콜드 2건, 8초 초과 0 | 완료(시연 한정) | `docs/blog/drafts/c-serving.md`, `ai` 154ff44 |
| P10 | 배치 접수 1,000주문 52.5초, 5,000주문 272초(커넥션 1개 전유). 동시 5,000배치 2건은 같은 토트 선택→3분 32초 대기 후 전체 롤백 | `ToteAllocator`가 배송단위마다 IDLE 토트 33,226행을 엔티티로 적재해 첫 행만 씀(주문당 53ms, DB는 12ms·LIMIT 1이면 2.3ms). READ COMMITTED에서 미커밋 배정 안 보임 | 없음(과제). `LIMIT 1 FOR UPDATE SKIP LOCKED` + 500주문 청크. 사전 배정은 피킹 지시 LPN 모사로 가정 명시 | 실행 5 후 IDLE 토트 39,100개 → 58.2초로 더 느려짐(비례 확인) | 미해결 | `docs/evidence/loadtest/README.md` 실행 3 |

## 2등급 — 부품 문제, 검증됨 (12건)

| # | 문제 | 원인 | 해결 | 검증 | 근거 |
| --- | --- | --- | --- | --- | --- |
| S1 | 동시 포장에서 `stock_qty` 감소분이 원장의 절반(776~853 vs 1,488~1,702) — lost update | `findById` 후 `findByGtinForUpdate`가 영속성 컨텍스트의 잠금 전 인스턴스 반환 | `findGtinById`로 값만 조회. 원장 전환으로 경로 자체 제거 | 실행 5 후 OUTBOUND 합 = PACKED 합 47,662. `ConcurrentStockIT` 8스레드 | loadtest README 174~175, backend 6adec19·fdab7f0 |
| S2 | 재고 조정이 원장에만 기록돼 `stock_qty` 약 120 → 출고지시 149건 이후 전부 거절 | 재고가 두 곳 | 원장 단일 진실, 조정 API 한 곳(D-L7) | 구조로 제거 | loadtest README 59 |
| S3 | 집계기 동시 실행 시 이중 반영(정답 93, 결과 90) | CTE가 delta를 미리 계산, 재검사 뒤 통째로 더함 | 상관 서브쿼리 UPDATE(EvalPlanQual 재검사 활용) | psql 재현, `StockBalanceCollectorIT` 2스레드×15회 | `ledger-review-repro.md` 5~137 |
| S4 | 같은 멱등 키 동시 조정 8건 중 7건 500 | 유니크 위반 후 같은 트랜잭션에서 재조회 불가 | `NOT_SUPPORTED` + 위반 시 승자 재조회 `duplicated:true`. `adjustInternal` 분리 | 8/8 200, txId 1개 | `ledger-review-repro.md` 173~209, `InventoryAdjustmentControllerIT` |
| S5 | 대조기에서 상품 1 복구 실패가 상품 2 복구까지 롤백 | 메서드 하나의 `@Transactional` | 상품별 `TransactionTemplate` | `StockReconcilerTest` | `ledger-review-repro.md` 139~171 |
| S6 | 리셋과 집계가 겹치면 옛 원장이 스냅샷에 재반영 | 리셋이 UPDATE(0,0) → 락 대기 집계가 재검사 후 재합산 | 스냅샷 행 DELETE, 다음 집계가 INSERT_MISSING | `DemoResetIT` 역검증 | `.superpowers/sdd/final-fix-report.md` |
| S7 | `now()` 기준 정착 판정의 반례 | 트랜잭션 시작 시각이라 일찍 시작해 늦게 INSERT한 행이 정착으로 오판 | `clock_timestamp()` 기록, `statement_timestamp()` 판정 | 논증(전용 테스트 없음) | 같은 파일 15~24 |
| S8 | 추론 호출(콜드 최대 10초)이 트랜잭션 안에서 커넥션 점유 | 같은 빈 안 호출은 프록시를 안 탐 | `MeasurementWriter` 분리로 트랜잭션 밖 호출 | `MeasurementTransactionBoundaryIT` | backend 74bf582 |
| S9 | 편성 국소 탐색 NPE(API였다면 500) | 낱개를 뺀 쪽 수용 여부 미검사 | 뺀 쪽도 검사, 벤치마크 실제 주문을 회귀 테스트로 | `CartonizerWeightTest` | backend 0b67425 |
| S10 | 매핑 없는 라우트·메서드·enum 파라미터가 500 | catch-all 핸들러가 `NoResourceFoundException`까지 삼킴 | 404/405/400 분리 | `RouteNotFoundIT` | backend 9501d8b·083e38e·fa7a693 |
| S11 | 테스트가 실제 시연 사진을 3바이트 가짜로 덮어써 병합됨 | 보관소 경로 공유 | 테스트 경로 분리, JPEG 표식·크기 검사, `--delete` 결함 수정 | — | backend 114a1c9·3ccfcab·b02bd83 |
| S12 | 토트 부족 시 일부만 접수된 상태 | — | 배치 전체 롤백(테스트는 트랜잭션 없이 실행해야 검증 성립) | `OrdersImportToteShortageIT` | backend 13f1bda |

## 과제 — 발견했으나 미해결 (7건)

| # | 항목 | 근거 수치 | 방향 |
| --- | --- | --- | --- |
| R1 | 토트 전체 적재·동시 배치 롤백(P10) | 주문당 53→58ms, 5,000건 롤백 | SKIP LOCKED + 청크 |
| R2 | 업로드 큐 유실(P7) | PENDING 1,155장 | Outbox 재처리, 배포 재시작 유실이 사업 근거 |
| R3 | 박스 재고 행 락이 포화 처리량 상한 | 풀 20 이후 처리량 정체, `Lock:tuple` 6→32세션, 묶음 77%가 박스 2종 | `countByLineIdAndStatus`를 트랜잭션 밖으로, `lock_timeout` 실험 |
| R4 | 정착 60초 전제를 강제할 수단 없음 | — | `transaction_timeout`을 원장 쓰기 트랜잭션에만(앱 롤 전체면 272초 배치가 끊김) |
| R5 | 수정 전 빌드에서 커서 누락 실제 빈도 미측정 | 산식 상한 3분 54행(0.9%) | 부하 환경에서 mismatch 게이지 집계 |
| R6 | 서버 2대 전환 시 스케줄러 중복 실행 | — | ShedLock(`lockAtMostFor` 30초) 또는 워커 분리 |
| R7 | `connectionTimeout` 3초 여유 4ms | 획득 max 2.996초(작업자 100명 큐) | 작업자 수 늘린 측정, R3 해결 후 재측정 |

## 방법 — 검증 방법 자체가 내용인 항목 (테크블로그 재료)

| # | 사건 | 의미 |
| --- | --- | --- |
| M1 | 사전 예측 B("풀 5 이상이면 획득 p95 1ms 미만")가 틀림(실측 1.6~1.7ms) → 가설 세워 `aliveBypassWindowMs` 600초로 검증(0.1ms) → "사후 해석"으로 명시 | 예측을 먼저 적고, 틀리면 틀렸다고 쓴다 |
| M2 | 표류 원인 후보 2개(RDS 크레딧, 대조기)를 예측 먼저 적고 기각. 크레딧 0에서도 처리량 평탄, 대조기는 분당 0.3 CPU초 | 반증 가능한 예측으로 원인을 좁힌다 |
| M3 | 원장 되돌림 없이 돌린 스윕에서 "풀 30 붕괴"(56.7건/s) → 되돌리자 137.6건/s. 주장과 그 위에 세운 보완 규칙 근거 철회 | 조건 사이 데이터 상태를 같게 하지 않으면 설정 효과와 데이터 증가 효과를 구분 못 한다 |
| M4 | 수집 도구 `collect.py`가 같은 초 표본 2건을 1초로 나눠 세션 수 최대 2배 과대(풀 40에서 49.4 — 커넥션 40개라 불가능) → 표본 단위로 재계산, 52실행 중 12개 값 변경, 규칙 판정 불변 | 불가능한 값이 도구 버그의 신호 |
| M5 | k6 스크립트 결함 3건: 사이클 동기화(pending 9 주기적), gracefulStop 반복 포함, 상세 500 뒤 무게 1.0kg 완료 전송(409 연쇄) — 무효 실행 `invalid/`로 분리 | 도구 결함으로 나온 수치는 버리고 사유를 남긴다 |
| M6 | 사전 규칙 충돌(처리량 규칙 20 vs DB 대기 규칙 10) 처리와 타임아웃 1초→3초 사후 변경을 PLAN 변경 기록에 남김 | 사후 결정을 사전 결정처럼 쓰지 않는다 |
| M7 | 글 F 근거 비평: "대조기도 복구 못함" 주장이 검증된 적 없음 → R1 재측정으로 정정. 검증 실험이 스스로 전제(창 3초·대기 4초)를 어겼음 → 재실행 | 글의 중심 주장도 재측정 대상 |
| M8 | 데드락 로그 ctid로 상품 쌍 복원 불가 → 품목 수별 실패율(1개 13.8%~5개 82.6%)로 대체 | 못 잰 것은 다른 각도의 계측으로 |
| M9 | 운영 측정 입력이 사진 한 장 3번 복제라 추론 왜곡(스팸 49×48×20cm) → 실제 3뷰로 교체(10.4×10.1×19.7, 정답 10.1×10.1×19.8) | 입력 데이터 검증 없이는 측정도 무효 |
| M10 | 외삽 오차: RDS/로컬 배율 가정 2.0 → 실측 2.5, 무부하 CPU 예측 16~18% → 실측 26~30% | 외삽은 조건을 명시하고 실측으로 닫는다 |

## 인프라·CI 사고 (아키텍처 절 또는 부록)

| # | 사고 | 원인 | 해결 | 근거 |
| --- | --- | --- | --- | --- |
| I1 | 팀 저장소 main 베이스 PR 병합 → 옛 코드 배포 → 백업 복원(2026-08-25) | 기본 브랜치가 develop | 트리거 develop으로, 공개 저장소에서는 main | backend c61c61c·b9cdd2f |
| I2 | GitHub Actions `AssumeRoleWithWebIdentity` 거부 | 조직 OIDC `sub`가 ID형 `repo:cj-ai-sw@316033991/...` | 신뢰 정책에 ID형 병기 | ai 9acf1ac, `infra/iam.tf` |
| I3 | 새 EC2가 apt·SSM·SSH 전부 불통 | 기본 서브넷이 IGW 경로 없는 라우트 테이블에 연결 | `aws_route` 0.0.0.0/0 추가 | 포폴 7b03893, `network.tf` |
| I4 | apply마다 모니터링 포트 규칙 소실 | SG 인라인 규칙과 독립 규칙 혼용 | 전부 독립 리소스로 | 포폴 a69b260 |
| I5 | 공인 IP가 두 주소를 오가 실험 중 2회 접속 단절 | SG `/32` 단일 | `my_extra_ips` 목록 | 포폴 2a8951d |
| I6 | 첫 ECR 배포 `aws: command not found` | 인스턴스에 CLI 없음 | CI가 ECR 토큰을 0600 파일로 전달 | backend 75c33ad |
| I7 | 별칭 이동 직후 첫 촬영 `MEASURE_FAILED` | 콜드 Init 9,999ms > 8초 | 배포 잡 워밍 호출 | `docs/blog/sources.md` |
| I8 | 게이트 첫 실행 실패 | CI 역할에 `lambda:InvokeFunction` 없음 | 권한 추가 | `docs/evidence/eval/gate-runs/README.md` |
| I9 | 컨테이너에서 인스턴스 프로파일 자격증명 못 받음 | IMDS hop limit | 2로 설정 | `ec2.tf` |
| I10 | 토큰 노출 위험 | argv·`.git/config`·ARG | `GIT_ASKPASS` 0600, BuildKit secret, `local/` gitignore | backend b9d690a, ai c8e91fd |

## 반영 전에 맞춰야 할 불일치

1. Lambda 호출 수: `docs/stories/story-02-capture-latency.md`는 332건·p95 611ms, `section-full.md`·`c-serving.md`는 319건·p95 609ms. 332는 INIT_REPORT 13건 포함 이벤트 수. 319로 통일.
2. 피크 3배 3개 이상 겹칠 확률: PLAN 0.45%, 글 G 0.49%. 0.49%로.
3. 운영 E2E: `section-full.md` 문제 2는 추정 "0.8초 안팎", 실측은 p95 796ms→611ms. 실측으로 교체.
4. 글 G 결론 "ADVANCE 비용은 아직 줄이지 못했다"·글 F 남은 과제 ADVANCE 항목: 브랜치 병합 시 "수정·검증 완료"로.
5. `StockBalanceCollectorSettleIT` Javadoc "창 2초" vs 설정 5초.
6. `application.yml` 종횡비 주석 7.7 vs 커밋 본문 8.1.
7. 저장소 공개 전: `infra/apply1~3.log`가 git 추적됨(내용 확인), `tools/measure/measure_e2e.py`에 스크래치패드 절대경로 하드코딩.

## 포폴 구조 제안

현재 Google Doc 구조(문제 1 박스 추천 / 문제 2 속도 / 문제 3 정확도 게이트)에 다음을 더한다.

- 문제 4 "동시 포장과 재고 정합성": P1 → S1·S2(발견 경로) → P2 → P3. 부하 테스트 → 원장 전환 → 코드 검토 결함 → 실험 부산물 결함까지 한 사건 사슬. 글 F가 본문.
- 문제 5 "커넥션 풀을 실측으로 정하기": P4 + M1~M6. 글 G가 본문. 결과보다 방법이 내용.
- 문제 2 속도 절에 P6·P7 추가(비동기화가 숨긴 실패), 문제 1에 P5의 벤치마크 NPE(S9).
- 남은 과제 절: R1~R7을 수치와 함께. 특히 R1(토트)·R2(업로드 큐)는 부하 테스트에서 찾고도 못 고친 것이라 감추지 않는다.
