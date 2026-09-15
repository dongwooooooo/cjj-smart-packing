# cjj-portfolio — VisionAI 기반 물류 스마트 패킹 고도화

CJ Campus AI SW 프로젝트(2026-08)에서 만든 풀필먼트 검수·포장 판단 시스템을 포트폴리오용으로 고도화한 작업본이다. 팀 저장소(`cj-ai-sw` 조직)는 수정하지 않고, 팀 저장소의 develop 시점 코드를 복제한 뒤 이 디렉터리 안에서만 작업했다. 원격 저장소는 아직 연결하지 않았다.

## 구성

| 경로 | 내용 | 출처 |
| --- | --- | --- |
| `backend/` | Spring Boot 4.1 백엔드. `main` = 팀 develop(2026-08-31) + 무게·요금 목적함수 편성 + 촬영 사진 업로드 비동기화 | 팀 저장소 develop 복제 후 두 브랜치 병합 |
| `ai/` | 추론 API·Lambda 배포·고정셋 평가 하네스·정확도 게이트. `main` = 팀 main + `eval/` | 팀 저장소 main 복제 |
| `docs/stories/` | 설계 문서 3건(사내 기술문서 7절 양식) | 2026-09-15 작성 |
| `docs/portfolio/` | 포트폴리오 절 본문 3건(교열 완료)과 절 초안 v1 | Google Doc에 옮길 원고 |
| `docs/evidence/` | 측정·평가·벤치마크 원본(JSON, 로그, 표) | 2026-09-14~15 실측 |
| `docs/briefs/` | 구현을 맡길 때 쓴 브리프 2건 | 결정 사항의 원문 |
| `tools/measure/` | 촬영 응답 구간 측정: compose 오버레이(RIE·MinIO), 측정 스크립트, 드라이브 복사 스크립트 | |
| `tools/eval/` | EC2에서 돌린 모델 변형 평가·OpenVINO 비교 스크립트 | |
| `tools/infra/` | 평가용 EC2 Terraform(1대, 사용 후 destroy) | |

## 문제 3건 요약

| 문제 | 결론 | 근거 |
| --- | --- | --- |
| 1. 박스 추천에 무게 반영 | 편성 목적함수를 박스 수·부피에서 총 배송비로 교체. 낱개 초과 무게 거부, 출고 무게 검수 추가. 5,000주문 편성 21초, 초선형 증가 없음. 벤치마크가 국소 탐색 결함 1건을 찾아 수정 | `docs/stories/story-01`, `docs/evidence/benchmark/` |
| 2. 촬영 응답 1초 SLO | 백엔드 경로 p50 90~220ms 실측. 저장 구간이 최대여서 사진 업로드를 커밋 뒤 비동기로 분리, 저장 구간 p95 36→12ms | `docs/stories/story-02`, `docs/evidence/measurement/` |
| 3. 모델 교체 정확도 게이트 | 고정셋 2,024품목 평가 하네스와 비열화·절대 상한 기준. INT8 변형 3종 차단(±3cm 62.5%→22.6%), FP16·OpenVINO는 통과했으나 속도 이득 없음 | `docs/stories/story-03`, `docs/evidence/eval/`, `ai/eval/` |

## 실행

- 백엔드 테스트: `cd backend && ./gradlew test --no-daemon` (Java 25 toolchain 자동 설치). 편성 벤치마크는 `./gradlew benchmark`.
- 게이트 테스트: `cd ai && python3 -m pytest eval/test_gate.py`.
- 촬영 구간 측정: `tools/measure/docker-compose.measure.yml`을 `-p cjj-measure`로 기동한다. 같은 머신의 다른 compose 프로젝트와 이름이 겹치지 않도록 프로젝트명을 반드시 지정한다.

## 미결

- 촬영 응답(1-3)의 사진 주소를 업로드 완료 전에 발급하는 계약. 현재는 한계로 문서화.
- 게이트의 파이프라인 연결(평가 데이터 저장소 결정 선행).
- 벤치마크 수치 기준 실행 선택(23:36 실행과 23:38 재실행이 다름).
