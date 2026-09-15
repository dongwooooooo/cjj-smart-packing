# 브리프 — 카토나이제이션 무게 축 추가 (C안: 목적함수를 배송비로)

작업 위치: `/Users/idong-u/cjj/backend-weight` (git worktree, 브랜치 `feat/weight-cartonization`, base develop).
다른 워크트리(`/Users/idong-u/cjj/backend`)는 건드리지 않는다. 푸시하지 않는다. 커밋은 단위별로.
빌드·테스트: `./gradlew test --no-daemon` (Java 25 toolchain 자동). Docker 안 빌드 금지.
문서·주석 한국어, 코드 영어. 코드 스타일은 기존 파일(`orders/packing/*`)을 따른다.

## 배경 (왜)

현 편성(`Cartonizer`)은 목적함수 = 박스 수 최소 → 동점이면 총 부피 최소. 무게는 어디에도 없다.
CJ 현업 심사에서 "무게 고려했냐"는 질문이 나왔다. 택배 요금은 세 변의 합 구간과 무게 구간 중
높은 쪽으로 정해지므로, 무게가 없으면 요금이 한 구간 올라가는 편성을 최적이라고 낸다.

## 결정 (확정 — 바꾸지 말 것)

1. 목적함수를 **총 배송비 최소**로 바꾼다. 동점이면 박스 수, 그다음 총 부피 (기존 순서 유지).
2. 배송단위 요금 = 요금 구간표에서 `max(세변합 구간, 무게 구간)`. 구간표는 기준정보 테이블 `shipping_rate_tier`.
3. 하드 제약(넘으면 그 단위는 불가 → 분할, 낱개 하나가 넘으면 `OVERSIZED_ITEM` 거부와 같은 방식으로 `OVERWEIGHT_ITEM` 거부):
   - 세변합 ≤ 160cm, 최장변 ≤ 100cm, 단위 총무게 ≤ 25kg. 값은 설정(`packing.carrier.*`)으로 뺀다.
4. 세변합·최장변 판정은 **박스 외치수** 기준. 외치수 = 내치수 + 판두께×2. 판두께는 설정 `packing.board-thickness-cm` 기본 0.5 (실측 근거 없음 — 주석에 명시).
5. 단위 총무게 = Σ 상품 무게(`product.weight_kg`, 이미 있음) + 박스 자체 무게(`box_type.tare_weight_kg`, 신규 컬럼, seed 0.0 — 값 미확인 주석).
6. 출고 무게 검수: 포장완료(`POST /shipments/{id}/complete`) 요청에 선택 필드 `measuredWeightKg` 추가. 값이 오면 예상 총무게와 비교해 허용 오차 밖이면 `409 WEIGHT_MISMATCH`(detail: expectedKg, measuredKg, toleranceKg). 허용 오차 = `max(packing.weight-check.min-tolerance-kg 기본 0.1, expected × packing.weight-check.tolerance-ratio 기본 0.03)` — 둘 다 근거 없는 잠정값, 설정으로 뺀다. 값이 없으면 검수 생략(기존 호출 호환).

## 요금 구간 seed (CJ대한통운 표준운임 2024, 파스토 가이드 인용 — 2026 최신표는 재확인 표시)

| rank | tier | max_sum_cm | max_weight_kg | price_krw (동일권역) |
|---|---|---|---|---|
| 1 | 극소형 | 80  | 2  | 5000 |
| 2 | 소형   | 100 | 5  | 6000 |
| 3 | 중형   | 120 | 10 | 7000 |
| 4 | 대형   | 140 | 15 | 8000 |
| 5 | 특대형 | 160 | 20 | 9000 |

하드 제약 기본값은 이 표의 최상단과 맞춘다: 세변합 160cm, 무게 **20kg**(결정 3의 25kg를 20으로 정정), 최장변 100cm.
출처(마이그레이션 주석에 URL): 파스토 2024 택배사 요금 비교 https://guide-kr.fassto.ai/d4204e29-29fd-4e91-9b64-3784764a4fc2 , CJ 공식 https://www.cjlogistics.com/ko/utility/parcel-price (접속 실패로 미대조), 우체국 30kg https://smartpacker.kr/guide/postbox-size-guide/
price_krw는 NOT NULL. `rank`는 요금 동률 대비 정렬용.

## 구현 단위 (순서대로, 단위마다 테스트 green + 커밋)

U1. 스키마 — Flyway `V13__shipping_rate_tier_and_box_weight.sql`: `shipping_rate_tier(id, name, rank, max_sum_cm, max_weight_kg, price_krw NULL)` + seed 4행, `box_type.tare_weight_kg DECIMAL(6,3) NOT NULL DEFAULT 0`. 기존 seed 파일 수정 금지(체크섬).
U2. 도메인 — `PackItem`에 `weightKg` 추가(BlockFactory에서 product 무게 주입), `CatalogBox`에 `tareWeightKg`·외치수 계산, 새 `RateTable`(구간 목록 → 단위 요금·구간 판정), `CarrierLimits`(하드 제약).
U3. 편성 — `Cartonizer` 목적함수 교체: `cost(units) = (Σ요금, 박스수, Σ부피)` 사전식 비교. `minBox`는 "치수 수용 + 하드 제약 통과" 박스 중 **요금 최소, 동점이면 부피 최소**로. FFD 정렬 기준은 유지(부피 내림차순). 통째 시도도 같은 기준.
U4. 거부 — 낱개 하나가 25kg 초과면 `OVERWEIGHT_ITEM`(2층 거부, detail gtin·weightKg). 접수 응답·문서(`docs/orders-import-spec.md` §3) 갱신.
U5. 출고 검수 — complete 요청 `measuredWeightKg`(선택), `WEIGHT_MISMATCH` 에러코드, 응답에 `expectedWeightKg` 포함. 상세 조회(3-2)에도 `expectedWeightKg` 노출.
U6. 테스트 — 기존 packing 테스트 21개 green 유지 + 추가: (a) 부피는 들어가는데 무게로 구간이 올라 분할이 더 싼 케이스, (b) 무게 하드 제약으로 분할, (c) 낱개 초과 거부, (d) 같은 입력 반복 실행 결정성, (e) 무게 검수 통과/불일치, (f) 요금 NULL 구간 정렬.
U7. 문서 — `docs/orders-import-spec.md` §4-0 목적함수·§4-6 파라미터 갱신, `docs/04-decisions.md`(docs 저장소가 아니라 backend-weight 안 문서만; docs 저장소는 건드리지 않음)에 결정 요약 파일 `docs/decisions-weight.md` 신규.

## 하지 말 것

- 적재 순서(무거운 것 아래) 규칙 추가 금지 — 내하중 데이터 없어 검증 불가, 한계로만 문서화.
- 목적함수에 없는 가중치·휴리스틱 임의 추가 금지.
- 슈퍼블록·시도 다양화 구현 금지(별도 성능 과제).
- `src/main/resources/db/migration/V1~V12` 수정 금지.

## 완료 보고 형식

단위별: 바뀐 파일, 테스트 결과(개수·green), 결정이 필요한 지점(있으면 멈추고 보고). 마지막에 `./gradlew test` 전체 결과 요약.
