# 블로그 소재 지도 — VisionAI 물류 스마트 패킹

작성일 2026-09-16. 포트폴리오 절(`docs/portfolio/section-full.md`)이 결과 중심이라면, 블로그는 개발 과정을 시간 순으로 쓴다. 이 문서는 그 과정을 재구성할 때 쓸 원본 소스의 위치와 활용 방법을 정리한 것이다. 글은 아직 쓰지 않았다.

경로 표기: `team/` = `~/cjj/`(팀 저장소 클론, 수정 금지), `pf/` = `~/d/cjj-portfolio/`, `sess/` = `~/.claude/projects/-Users-idong-u-cjj/`.

## 1. 시간표 (git 로그·결정 이력 기준)

| 날짜 | 사건 | 원본 |
| --- | --- | --- |
| 08.20 | 저장소 4개 초기화. Flyway 스키마·seed·Spring 스캐폴드. 결정 D-06~D-17 (역할 3분할, 재피킹 제거, 박스 규칙 초안, GPU 파드 8초 계약) | `team/backend` da5212e, `team/docs/04-decisions.md` |
| 08.21 | 축 규약 D-18, 재고 영역 제거 D-19, 재피킹 UI-only D-20. 카토나이제이션 조사 카드 작성 | `team/docs`, `~/d/knowledge/concepts/cartonization.md` |
| 08.22 | 수기 등록 경로 제거 D-21 | `team/docs` 5aeaf15 |
| 08.23 | 출고지시 명세 v1.1, 카토나이제이션 구현(배치 판정·편성·블록화), 재고 단일 창구, 상용 API 4종 대조 | `team/backend` 2098c95, `team/docs/research/fulfillment-outbound-api-benchmark.md` |
| 08.24 | 접수 1·2층 검증, 도메인 경계 리팩터, 계약 확정 D-22, 촬영·추론 API 1-3. ai 저장소 시작(FastAPI 스켈레톤, EC2·Lambda 배포 스크립트) | `team/backend` 0acd0c9~08d15fe, `team/ai` 214d513~c8e91fd |
| 08.25 | ONNX Runtime 전환, GitHub Actions OIDC, SSM 배포, Lambda 실연동 D-24, 포장 완료 단일 트랜잭션, 시연 데이터 서브시스템 | `team/ai` 154ff44·10db241, `team/backend` 1b39778·0729ce2, `team/tasks/2026-08-25-*.md` |
| 08.26 | 추론 호출 트랜잭션 밖으로, RDS 분리, 시연 사진 S3 이관, 리셋 끝 워밍. 모델 로컬 평가 리포트(VS 2,024) | `team/backend` 74bf582·aec6d67, `team/eval/REPORT.md` |
| 08.27~30 | 이미지 빌드 CI 전환·ECR pull 배포, API 키 가드, 시연 상품 CJ제일제당 12종, 박스 F호 추가, 시연 데이터 조정 PR 다수 | `team/backend` 478b514~943e02a |
| 08.31 | 결과 발표·시연. CloudWatch 호출 332건. 심사단 질문 "무게 고려했냐" | `pf/docs/evidence/measurement/lambda-report-events.json`, 사용자 기억 |
| 09.09 | 모델 백업 확보(HF 전체 + ONNX) | `team/model-archive/…-20260909/BACKUP-INFO.md` |
| 09.14 | 포폴 구조 확정. 무게·요금 목적함수 편성 구현(커밋 7), 벤치마크로 NPE 발견·수정, 촬영 구간 로컬 실측(RIE) | `pf/backend` f871237~f1a4d3f, `pf/docs/evidence/measurement/` |
| 09.15 | EC2 c7i-flex.large에서 FP16·INT8·OpenVINO 평가, 게이트 코드, 사진 업로드 비동기화 D-27 | `pf/ai` 931882e, `pf/backend` 39a8464~faeaf1f, `pf/docs/evidence/eval/` |
| 09.16 | 병합·테스트 241 통과, 공개 저장소 발행, 포폴 절 완성 | `pf/` c183e47 |

## 2. 글 후보와 소스 배정

각 글은 "문제 → 원인 → 시도 → 결과" 순서로 쓴다. 실패한 시도를 남긴다. 아래 표의 "핵심 장면"은 글의 훅이 될 사건이다.

### 글 A. 결정 이력으로 3인 풀스택 팀을 운영한 방법 (팀장 관점, 08.20~08.25)

| 핵심 장면 | 소스 | 활용 |
| --- | --- | --- |
| 원본 MVP 문서에서 박스 규칙이 누락돼 개발 착수 불가(D-11) | `team/docs/04-decisions.md` D-11, `team/docs/01-mvp.md` | 문제 제기 |
| 도메인 수직 분할과 교차 계약 표 | `team/docs/05-team-plan.md` §1~§3 | 구조 설명 |
| 기능 제거 결정 3건과 이유(D-06/D-19/D-21), 재논의 방지(D-20) | `team/docs/04-decisions.md` | 결정 사례 |
| 계약 확정을 상용 API 4종 대조로(D-22) | `team/docs/research/fulfillment-outbound-api-benchmark.md` | 근거 수집 방식 |
| 도메인 간 접근 규칙, 엔티티 소유 표 | `team/backend` 348510a·aba0512 커밋과 `backend/README.md` | 코드 구조 |
| 기본 브랜치 develop인데 main 베이스 PR 병합 사고(08.25) | `~/.claude/…/memory/cj-ai-serving-pipeline.md` 주의점 | 실패 사례 |
| 세션 간 에이전트 협업(핸드오프 브리프) | `team/tasks/2026-08-25-backend-lambda-inference-handoff.md`, `sess/f01211db` | 작업 방식 (블로그 노출 여부 결정 필요) |

### 글 B. 부피 근사가 아닌 배치 기반 박스 추천, 그리고 무게 (08.21~08.24, 09.14)

| 핵심 장면 | 소스 | 활용 |
| --- | --- | --- |
| 25×25×20 두 개가 30³ 박스에 안 들어가는 사례, 박스 라인업 비례 관계 부재 | `pf/docs/portfolio/problem1-cartonization.md`, `team/backend/docs/orders-import-spec.md` §4 | 문제 제기 |
| extreme point·FFD·국소 탐색 선택과 6방향 회전 근거 주석 | `team/backend` 2098c95·2834f68, `~/d/knowledge/concepts/cartonization.md`(출처 URL 포함) | 설계 근거 |
| 리뷰 반영 커밋(완충재 표시 복원, 경계 방어) | `team/backend` 617fc5f·bf77c8e | 리뷰 과정 |
| 심사단 질문 "무게 고려했냐" | 사용자 기억(발표 08.31) | 2부 훅 |
| 무게 3안 비교와 C안(총 배송비 목적함수) 채택, 잠정값 목록 | `pf/backend/docs/decisions-weight.md`, `pf/docs/briefs/brief-weight-cartonization.md` | 결정 |
| CJ대한통운 2024 요금 구간(파스토 가이드 인용) | `pf/backend` V13 마이그레이션, 결정 문서의 출처 | 기준정보 |
| 벤치마크 첫 실행 NPE와 원인(뺀 쪽 미검사) | `pf/backend` 0b67425, `pf/docs/evidence/benchmark/bench.log`(실패 로그)·`bench2.log`(정본) | 실패 사례 |
| 5,000주문 편성 시간, 상위 10건 분석 | `pf/docs/evidence/benchmark/cartonization-benchmark-rerun-2338.md` | 결과 |
| 설계 문서 7절 양식본 | `pf/docs/stories/story-01-cartonization-weight.md` | 초안 골격 |

### 글 C. GPU 전제 8초 계약을 CPU Lambda로 (08.24~08.26)

| 핵심 장면 | 소스 | 활용 |
| --- | --- | --- |
| CPU torch 5.87초 실측과 8초 계약(D-15) | `team/docs/04-decisions.md` D-15 | 문제 제기 |
| 잠정 계약(JSON productId)과 실제 Lambda(multipart 3장)의 불일치 표 | `team/tasks/2026-08-25-backend-lambda-inference-notes.md` Step 1 | 훅 |
| 설계 갈림길 4개(이미지 경로·호출 방식·confidence·콜드스타트)와 확정 | 같은 파일 Step 2~3, D-24 | 결정 |
| torch→ONNX 1,070→185ms, 로드 3.10→0.22초, max diff | `team/ai/inference/README.md` 로컬 실측 절 | 결과 |
| 2단계 이미지 빌드, 토큰을 ARG/ENV로 받지 않는 이유, CPU 전용 torch | `team/ai/docs/lambda-deploy.md` | 설계 근거 |
| OIDC sub가 ID형이라 이름 기반 신뢰 정책 거부 | `team/ai` 9acf1ac, `team/ai/docs/cicd.md` §1, 메모리 주의점 | 실패 사례 |
| Lambda 3,008MB 쿼터, provisioned concurrency 시연 시간대 예약 | D-24, 메모리 | 결정 |
| 추론 호출을 트랜잭션 밖으로(커넥션 점유) | `team/backend` 74bf582 | 후속 수정 |
| EC2 추론 트랙 폐기(인스턴스를 백엔드 서버로 전환) | `team/ai` 40e7470 | 기각 안 |
| SSM 배포·ECR pull 전환·API 키 가드 | `team/backend/docs/deploy.md`, 478b514·523526d | 배포 |
| 시연 기간 호출 분포 332건 | `pf/docs/evidence/measurement/lambda-report-events.json` | 운영 수치 |

### 글 D. 촬영 응답 1초 — 구간 실측과 저장 경로 비동기화 (09.14~09.15)

| 핵심 장면 | 소스 | 활용 |
| --- | --- | --- |
| 8초 계약이 기준값으로 무의미, 1초 근거(Nielsen, 상용 DWS) | `pf/docs/stories/story-02-capture-latency.md` §근거 | 문제 제기 |
| E2E 표본 1건(2.6초)만으로는 백엔드가 0.9초로 보였던 오판 | `pf/docs/evidence/measurement/measurement-results-2026-09-14.md` | 훅 |
| AWS 없이 Lambda 이미지를 RIE로 띄워 같은 Invoke 경로 재현 | `pf/tools/measure/docker-compose.measure.yml`, `measure_e2e.py`, `pf/backend` 757ec60 | 방법 |
| compose 프로젝트명 충돌로 다른 프로젝트 컨테이너를 덮을 뻔한 사고 | 메모리 `cjj-project-context.md` 함정 항목, `pf/README.md` 실행 절 | 실패 사례 |
| Docker 안 Gradle 빌드 실패 → 로컬 bootJar 우회 | 메모리, `tools/measure/docker-compose.measure.yml` dockerfile_inline | 우회 |
| 구간별 수치 표(490KB·57KB) | `measurement-results-2026-09-14.md`, `measure-*.json` 10건 | 결과 |
| 대안 5개와 비동기 업로드 채택, 실패 처리(upload_status) | `pf/backend/docs/decisions-async-image-store.md`, `pf/docs/briefs/brief-async-image-store.md` | 결정 |
| 병합 후 통합 테스트 경합과 Awaitility 수정 | `pf/backend` 7b91fa0 | 후속 수정 |
| 1-3 사진 주소 계약 유지 결정 | `pf/README.md` 결정 사항 | 한계 |

### 글 E. 재학습 없이 INT8은 안 된다 — 배포 전 정확도 게이트 (09.15)

| 핵심 장면 | 소스 | 활용 |
| --- | --- | --- |
| 학습 리포트 1.31cm vs 서빙 재평가 2.06cm 불일치 | `team/eval/REPORT.md` 해석 절, `team/ai/inference/config.json` val_mae | 문제 제기 |
| 상용 0.5cm·OIML 기준과 MAE 2cm 격차를 문서에 명시 | `pf/docs/stories/story-03-model-accuracy-gate.md` | 계약 설정 |
| 데이터를 로컬에 받지 않고 Drive→EC2 rclone 직송, 공용 client_id 쿼터 초과 → tps 4 | `pf/tools/measure/ec2_rclone_copy.sh`, 메모리 | 방법·실패 |
| 프리티어 플랜이 c7i.xlarge 거부 → c7i-flex.large | `pf/tools/infra/eval-ec2.tf`, 메모리 | 제약 |
| 정적 양자화 보정에서 OOM(RSS 3.5GB/4GB) → 스트리밍 리더·스왑, 백분위·엔트로피는 24표본도 OOM | `pf/tools/eval/eval_variants.py`, `pf/docs/evidence/eval/logs/run_d*.log` | 실패 사례 |
| 변형별 결과 표와 품목별 편차(중앙값 3.2cm, p95 7.5cm) | `pf/docs/evidence/eval/table.md`, `summary_*.json`, `per_item/` | 결과 |
| OpenVINO EP가 ORT CPU와 동급 | `pf/tools/eval/eval_openvino.py`, `summary_ov.json` | 기각 안 |
| 게이트 판정 함수와 테스트 5개, 픽스처 | `pf/ai/eval/gate.py`, `test_gate.py`, `eval/README.md` | 코드 |
| depthwise conv 양자화 민감성 근거 | 미확인 — 논문·문서 출처 필요 | 근거 보강 |

### 글 F (선택). 시연 데이터 서브시스템 (08.25~08.30)

| 핵심 장면 | 소스 | 활용 |
| --- | --- | --- |
| 시연용 데이터 파일·리셋·투입 API 설계 | `team/backend/docs/demo-subsystem-spec.md`, `team/backend/demo/scenario.md` | 설계 |
| 시연 상품 선정(CJ제일제당 12종, 치수 오차 기준) | `team/tasks/2026-08-26-demo-product-candidates.md`, `team/eval/cj_products.md`, `best_under_0.5cm_VS.md` | 선정 근거 |
| 사진 3바이트 깨짐, S3 빈 디렉토리 삭제 방지, 라인별 건수 맞춤 등 PR 20건 | `team/backend` 08.28~08.30 로그 | 시연 준비 실패 목록 |
| 발표 슬라이드 목차·부록 사양·대본 | `team/docs/final_presentation/`, `team/docs/research/presentation-script.md`, `team/도입부초안.pdf` | 발표 자료 |

## 3. 공통 소스

| 종류 | 위치 | 비고 |
| --- | --- | --- |
| 팀 저장소 git 로그·PR 본문 | `team/backend`(develop, 병합 PR 60), `team/ai`(10), `team/docs`(1), `team/frontend`(45). PR 본문 덤프 `pf/local/prs/{backend,ai,docs,frontend}.md`(git 제외) | 조직 저장소는 비공개(PRIVATE). 인용은 공개 저장소의 동일 코드로 한다 |
| 고도화 git 로그 | `pf/backend` 943e02a..7b91fa0(17 커밋), `pf/ai` 931882e | 공개 저장소 |
| 세션 기록(대화·결정 과정) | 발췌본 `pf/local/sessions/*.md`(git 제외) — 08.25 e828661e·0598f167(백엔드 실연동), 08.26 d1e12cc0(문제 정의·DWS), 08.30 f01211db(Lambda 실연동 에이전트), 09.14 cd2b0852(서빙 아키텍처 Q&A), 09.14 b0523626(데이터셋 위치), 09.15 d20b1044(평가·측정). 원본 `sess/*.jsonl`. 이번 세션 0c3bfd62는 종료 후 추출 | 추출 스크립트 `pf/tools/blog/extract_session.py`. 자격증명 노출 이력이 있어 발췌본은 공개 저장소에 넣지 않는다(`local/` gitignore) |
| 실측 원본 | `pf/docs/evidence/{measurement,eval,benchmark}` | JSON·로그·표 |
| 발표 자료 | `team/도입부초안.pdf`(08.27), `team/발표 시나리오.pdf`(08.21), `team/docs/final_presentation/` | 슬라이드 재사용 |
| 지식 카드 | `~/d/knowledge/concepts/cartonization.md` | 출처 URL 포함 |
| 그림 | `pf/docs/figures/fig1~4` | 포폴과 공용 |
| 기획·시장 조사 | `team/docs/research/problem-definition.md`, `market-structure-and-dws-rationale.md` | 도입부. CJ 청중용 프레임 주의(메모리 참조) |

## 4. 비어 있는 것

| 항목 | 상태 | 대응 |
| --- | --- | --- |
| 화면 캡처(입고·포장·대시보드) | `team/` 루트 PNG는 다른 프로젝트(WMS) 것. cjj 화면 캡처 없음 | 프론트를 로컬 기동해 캡처, 또는 발표 PDF 슬라이드 재사용 |
| AWS 콘솔 캡처(Lambda 설정, provisioned concurrency 예약) | 자원 삭제됨(09.14 확인). CloudWatch 로그 그룹만 잔존 | 로그 기반 표로 대체 |
| 심사단 질문 원문 | 기록 없음, 사용자 기억 | 발표 당일 메모 확인 |
| 팀 저장소 코드 인용 | 조직 저장소 비공개 확인(2026-09-16) | 공개 저장소(`dongwooooooo/cjj-smart-packing-*`)의 동일 코드로 인용 |
| AI-Hub 데이터 이용 조건 | 미확인 | 데이터 관련 사진·수치 공개 범위 확인 |
| depthwise conv 양자화 민감성 근거 | 미확인 | 출처 확보 후 글 E에 반영 |
| 프론트엔드 작업 기여 | 역할이 플랫폼·배치라 프론트 커밋은 타 팀원 | 글에서 다루지 않음 |

## 5. 다음 단계

1. 글 순서 결정. 후보: B(카토나이제이션) → C(서빙) → D(1초) → E(게이트) → A(팀 운영). F는 보류.
2. 화면 캡처 확보 방법 결정(로컬 기동 vs 발표 PDF).
3. 글 B부터 초안 착수. 세션 발췌본에서 결정 대화를 인용할 때는 자격증명·개인 식별 정보를 제거한 뒤 쓴다.

완료(2026-09-16): 세션 발췌 스크립트와 발췌본 7건, 팀 저장소 PR 본문 116건 수집(`local/`).
