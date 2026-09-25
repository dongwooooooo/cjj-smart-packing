# 원장 기반 재고 설계 — 포장 완료 락 제거와 정합성 검사

작성 2026-09-23. 대상 저장소 `backend`(cjj-portfolio 서브모듈). 상태: 승인(2026-09-23). 창고 1개, 화주·채널 구분 없음이 전제다.

## 1. 배경과 목표

부하 테스트 실행 4(2026-09-22)에서 포장 완료 트랜잭션이 상품 행을 `SELECT FOR UPDATE`로 잠그는 순서가 배송단위마다 달라 데드락이 났다. 작업자 10명에서 12%, 50명에서 40%가 500으로 끝났고, 품목 5개 배송단위는 82.6% 실패했다. 같은 날 재고 조정을 원장에만 넣고 `product.stock_qty`를 갱신하지 않아 가용 재고가 0이 되어 출고지시 전체가 거절됐다. 두 사고의 공통 원인은 재고 숫자가 원장(`inventory_tx`)과 잔고 컬럼(`product.stock_qty`) 두 곳에 있고, 잔고 갱신이 트랜잭션 안의 행 락에 묶여 있다는 것이다.

목표:

1. 포장 완료 경로에서 상품 행 락을 없앤다.
2. 원장을 재고의 유일한 진실로 두고, 잔고는 원장에서 유도한다.
3. 원장과 잔고가 어긋나면 60초 안에 자동 복구하고 지표로 드러낸다.
4. 재고 조정은 재전송해도 한 번만 반영된다.

성공 기준: 같은 토트 목록으로 50명 포장을 재실행했을 때 완료 500이 0건, 데드락 0건. 정합성 훼손 후 60초 안에 복구와 지표 상승. 기존 테스트 241건 통과.

## 2. 현재 구조

| 구성 | 현재 |
| --- | --- |
| 원장 `inventory_tx` | 증감 기록. `INBOUND`, `OUTBOUND_PACKED`, `ADJUST` |
| 잔고 `product.stock_qty` | 결과 숫자. 원장 기록과 같은 트랜잭션에서 행 락을 잡고 갱신 |
| 단일 창구 `StockMovementRecorder` | `recordInbound`, `recordOutboundPacked`, `adjust`. 세 메서드 모두 `findByGtinForUpdate` 뒤 `changeStockQty` |
| 가용 재고 `AvailableStockQuery.availableQty` | `stock_qty − 미포장 배정 수량(shipment_item 합)` |
| 포장 완료 `ShipmentCompleteService.complete` | 품목마다 상품 행 락·부족 검사·차감 → 박스 행 락·차감 → 토트 해제 → PACKED |
| 정합성 검사 | 없음 |
| 조정 경로 | `InventoryService.adjust` 내부 호출만. 시연 프로비저너는 `update product set stock_qty = 0` 직접 SQL도 사용 |

## 3. 바뀐 구조

재고가 바뀔 때는 원장에 행을 추가만 한다. 잔고는 집계기가 원장을 읽어 `stock_balance`에 적는다. 조회는 스냅샷에 아직 집계되지 않은 원장 행을 더해 답한다.

| 흐름 | 현재 | 변경 후 |
| --- | --- | --- |
| 입고 | 상품 행 락 → 잔고 +n → 원장 +n | 원장 +n |
| 출고지시 접수 가용 판단 | `stock_qty − 미포장 배정` | `stock_balance.qty + Σ(미집계 원장) − 미포장 배정` |
| 포장 완료 | 품목마다 상품 행 락·부족 검사·차감 → 박스 행 락 → 토트 해제 | 품목마다 원장 −n → 박스 행 락 → 토트 해제 |
| 재고 조정 | 내부 호출, 직접 SQL 혼재 | 조정 API 한 곳, 멱등 키 |
| 재고 조회 | `stock_qty` | `stock_balance.qty + Σ(미집계 원장)` |
| 집계 | 즉시(쓰기 트랜잭션 안) | 5초 주기 집계기 |
| 정합성 | 없음 | 60초 주기 대조기, 자동 복구, 지표 |

### 포장 완료 시간 순 (품목 사과·배, 박스 B호)

현재: 사과 행 락 → 사과 검사·차감 → 배 행 락 → 배 검사·차감 → B호 행 락·차감 → 토트 해제 → PACKED. 다른 작업자가 배→사과 순으로 들어오면 첫 두 단계에서 서로를 기다린다.

변경 후: 원장 사과 −1 → 원장 배 −2 → B호 행 락·차감 → 토트 해제 → PACKED. 트랜잭션이 잡는 행 락이 B호 하나라 순환이 생기지 않는다.

## 4. 결정 사항

### D-L1. 포장 완료의 재고 부족 검사 제거

포장 완료는 실물이 나갔다는 사실의 기록이다. 포장대에 실물이 있는데 시스템이 "재고 부족"으로 막는 상황은 실물 문제가 아니라 데이터 오류(잘못된 수기 조정, 원장·잔고 불일치)다. 시스템은 사실을 거부하지 않고 원장에 기록한다. 그 결과 잔고가 음수가 되면 실물과 장부가 어긋났다는 신호로 지표와 로그에 올린다. 재고 수용 판단은 출고지시 접수의 소프트 배정이 담당한다. `OUT_OF_STOCK`은 박스 재고에만 남는다. 기존 검사는 시연 단계의 방어 코드였고 프로덕트 관점에서는 결함이다.

### D-L2. 가용 재고 = 스냅샷 + 미집계 원장 차분 − 미포장 배정

집계 주기와 무관하게 정확하다. 단, 원장 행의 id 순서와 커밋 순서가 어긋날 수 있으므로(포장 완료가 원장 행을 넣은 뒤 박스 행 락을 기다린다) 집계기는 `id`만으로 접지 않고 정착 창(D-L5 참고)을 지난 행까지만 접는다. 원장을 쓰는 트랜잭션이 정착 창(기본 60초) 안에 끝난다는 전제 위에서 정확하다. 원장 전체 합계 방식은 상품별 원장이 수만 행이 되면 접수마다 집계 비용이 커서 기각. 스냅샷만 쓰는 방식은 집계 지연 동안 방금 입고된 수량이 가용에 안 보이고 방금 포장된 수량이 가용에 남아 기각.

### D-L3. `product.stock_qty` 컬럼은 남기되 읽기·쓰기 모두 중단

컬럼 삭제는 후속 마이그레이션으로 미룬다. 이번 변경이 문제를 일으키면 되돌릴 여지를 둔다. 코드에서 이 컬럼을 참조하는 곳은 전부 제거한다.

### D-L4. 잔고 스냅샷은 별도 테이블 `stock_balance`

`product` 행에 두면 집계기의 갱신이 상품 마스터 갱신(치수 확정 등)과 같은 행을 두고 경합한다. 별도 테이블이면 집계기는 자기 테이블만 만진다.

### D-L5. 집계는 5초 고정 지연 스케줄러, 정합성 검사는 60초

집계를 쓰기 트랜잭션 뒤 이벤트로 거는 방식은 이벤트 유실 시 집계가 멈추고, 스케줄러가 있으면 이벤트는 불필요해 기각. 5초는 시연 화면 새로고침 주기와 같은 값이다. 60초는 대조 쿼리(상품별 원장 전체 합)의 비용을 고려한 값이며 운영에서 조정한다.

구현 확정(2026-09-25, 최종 검토 C1): 집계 커서는 정착 창을 쓴다. `inventory_tx.created_at`은 DB가 `clock_timestamp()`로 기록하고, 집계기는 `created_at < statement_timestamp() − settle_seconds`인 행 가운데 첫 번째 "젊은" 행보다 작은 id까지만 `last_tx_id`를 올린다. 이렇게 하면 id를 먼저 받고 늦게 커밋한 행을 건너뛰지 않는다. `inventory.collector.settle-seconds` 기본 60. 전제: 원장을 쓰는 트랜잭션은 행을 넣은 뒤 60초 안에 커밋한다(포장 완료 약 1초). 이 전제가 깨지면 그 행은 대조기가 다음 주기에 복구할 때까지 조회값에서 빠진다.

### D-L6. 정합성 불일치는 원장 기준으로 자동 복구

스냅샷은 원장에서 유도한 값이라 어긋남의 원인은 코드 버그, 직접 SQL, 그리고 정착 창(D-L5)보다 오래 열린 원장 쓰기 트랜잭션뿐이다. 원장을 진실로 두고 스냅샷을 다시 만드는 것이 안전하다. 복구 사실은 지표와 로그로 남긴다. 원장 자체를 고치지는 않는다.

### D-L7. 조정은 API 한 곳, 멱등 키 필수

`POST /api/v1/admin/inventory/adjustments`. 오늘의 사고("원장만 넣고 잔고를 안 바꿈")는 조정 경로가 하나뿐이면 구조적으로 불가능하다. 시연 프로비저너의 직접 SQL도 이 경로로 바꾼다.

구현 중 확정(2026-09-24): 창구 `StockMovementRecorder`에 두 메서드를 둔다. `adjust(gtin, delta, idempotencyKey, reason)`는 관리자 API 전용으로 트랜잭션 밖(`NOT_SUPPORTED`)에서 돌아 같은 키의 동시 요청을 유니크 인덱스로 하나만 통과시키고 진 쪽은 이긴 기록을 다시 읽어 `duplicated`로 답한다. `adjustInternal(gtin, delta, reason)`은 재전송이 없는 내부 호출자(시연 프로비저너, 테스트 헬퍼)용으로 호출자의 트랜잭션에 참여한다 — 리셋 트랜잭션 안에서 방금 만든 상품 행을 봐야 하기 때문이다. 두 메서드 모두 원장 INSERT 한 줄이며, 컨트롤러는 `adjust`만 호출한다.

## 5. 데이터 모델 (V21 마이그레이션)

```sql
CREATE TABLE stock_balance (
    product_id  BIGINT PRIMARY KEY REFERENCES product (id),
    qty         INT       NOT NULL,
    last_tx_id  BIGINT    NOT NULL,          -- 이 id까지 집계됨. 원장이 없으면 0
    computed_at TIMESTAMP NOT NULL DEFAULT now()
);
INSERT INTO stock_balance (product_id, qty, last_tx_id)
SELECT p.id, COALESCE(SUM(t.qty_delta), 0), COALESCE(MAX(t.id), 0)
FROM product p LEFT JOIN inventory_tx t ON t.product_id = p.id GROUP BY p.id;

DROP INDEX ix_inventory_tx_product;
CREATE INDEX ix_inventory_tx_product_id ON inventory_tx (product_id, id);

ALTER TABLE inventory_tx ADD COLUMN idempotency_key VARCHAR(80);
CREATE UNIQUE INDEX ux_inventory_tx_idem ON inventory_tx (idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE VIEW v_stock_on_hand AS
SELECT b.product_id,
       b.qty + COALESCE((SELECT SUM(t.qty_delta) FROM inventory_tx t
                         WHERE t.product_id = b.product_id AND t.id > b.last_tx_id), 0) AS on_hand_qty,
       b.last_tx_id, b.computed_at
FROM stock_balance b;
```

상품이 새로 생기면 `stock_balance` 행은 첫 집계 때 `qty 0, last_tx_id 0`으로 만든다(집계기가 없는 행을 INSERT).

## 6. 컴포넌트

| 컴포넌트 | 역할 | 의존 |
| --- | --- | --- |
| `InventoryService` (수정) | `recordInbound`·`recordOutboundPacked`·`adjust`는 원장 INSERT만. `onHandQty`·`availableQty`는 D-L2 계산 | `InventoryTxRepository`, `StockBalanceRepository`, `ShipmentItemRepository` |
| `StockBalanceCollector` (신규) | 5초마다 `id > last_tx_id` 원장을 상품별로 합쳐 스냅샷 갱신. 상관 서브쿼리 UPDATE 한 문장으로 정착 창을 지난 행까지 접는다(D-L5 구현 확정). 동시 집계 시 뒤에 온 문장은 행 락을 얻은 뒤 재검사에서 파생 테이블의 `new_last`는 원래 값으로 고정되고 `WHERE b.last_tx_id < s.new_last`와 SET 범위 `(b.last_tx_id, new_last]`가 최신 커서로 재평가되어 겹치는 구간이 없다 — 이중 반영 없음(CTE 방식의 결함을 발견해 교체, 동시성 IT·커밋 순서 역전 IT·수동 재현으로 검증). `created_at`은 시간대 없는 TIMESTAMP 라 모든 쓰기가 같은 세션 시간대를 쓴다는 전제가 있다(직접 SQL 금지, D-L7) | `JdbcTemplate`, `MeterRegistry` |
| `StockReconciler` (신규) | 60초마다 상품별 원장 전체 합과 (스냅샷 + 차분)을 대조. 불일치는 상품마다 별도 트랜잭션으로 스냅샷 재작성(한 상품의 실패가 다른 상품을 막지 않음). 게이지 `inventory.reconcile.mismatch`(마지막 대조에서 **발견한** 불일치 상품 수 — 복구 실패분도 포함해 남은 문제가 보이게 한다)·`inventory.balance.negative`(음수 잔고 상품 수). 복구 실패는 WARN 로그 | `JdbcTemplate`, `TransactionTemplate`, `MeterRegistry` |
| 집계 지연 지표 (신규, `StockBalanceCollector` 안) | 집계 직후 게이지 `inventory.collector.lag_rows`(미집계 원장 행 수)·`inventory.collector.lag_seconds`(가장 오래된 미집계 행의 나이). 집계기가 멈추면 값이 계속 오른다. 정착 창(60초) 때문에 정상 상태에서도 `lag_seconds`는 창 근처에 머무르므로 알람 기준 초기값은 창 + 집계 주기 몇 번 = 75초 | `MeterRegistry` |
| 뷰 `v_stock_on_hand` (신규, V21) | 상품별 `스냅샷 + 미집계 원장 합`. 외부·BI가 잔고를 읽을 때는 이 뷰만 쓴다. `stock_balance` 직접 읽기는 금지 원칙 | — |
| `InventoryAdjustmentController` (신규) | `POST /api/v1/admin/inventory/adjustments` `{gtin, delta, idempotencyKey, reason}` → `{txId, gtin, delta, onHandQty, duplicated}` | `InventoryService` |
| `ShipmentCompleteService` (수정) | 상품 조회·락·부족 검사 제거. 품목마다 `recordOutboundPacked` 호출만 | 기존 |
| `DemoStateResetter`·`DemoProductProvisioner` (수정) | 리셋 시 `stock_balance` 행을 삭제(0 으로 갱신하면 동시에 도는 집계가 삭제 전 원장을 다시 더할 수 있다 — 최종 검토 I1). 다음 집계 때 `INSERT_MISSING`이 `(0,0)`을 만든다. 직접 SQL 대신 조정 경로 | 기존 |
| `ProductSummary`·`StockInResponse`·시연 상태 응답 (수정) | `stockQty`를 `onHandQty` 계산으로 채움 | `AvailableStockQuery` |

`StockMovementRecorder`의 `recordOutboundPacked` 계약 주석("부족 시 OUT_OF_STOCK")을 "잔고가 음수가 될 수 있고 정합성 검사가 보고한다"로 바꾼다.

## 7. 오류 처리

| 상황 | 처리 |
| --- | --- |
| 조정 키 중복 | 기존 원장 행을 찾아 `duplicated: true`로 200 응답. 같은 키에 다른 `delta`면 409 |
| 집계기 갱신 조건 불일치(다른 인스턴스가 먼저 갱신) | 해당 상품은 이번 주기를 건너뛴다. 다음 주기에 다시 계산 |
| 정합성 불일치 | 스냅샷 재작성, 게이지 증가, WARN 로그(상품, 원장 합, 스냅샷 값) |
| 잔고 음수 | 게이지 증가, WARN 로그. 포장은 막지 않는다 |
| 집계·대조 스케줄러 예외 | 로그 후 다음 주기 진행. 한 상품의 실패가 다른 상품을 막지 않도록 상품 단위로 try |

## 8. 테스트

순서대로 작성한다. 1번은 변경 전에 실패(데드락)를 확인해 두고 변경 후 통과시킨다.

1. **데드락 재현 IT** (Testcontainers Postgres): 품목 순서가 [A,B]인 배송단위와 [B,A]인 배송단위를 두 스레드가 동시에 완료. 현재 코드: 한쪽이 `CannotAcquireLockException`. 변경 후: 둘 다 PACKED, 원장 4행.
2. `availableQty` 단위 테스트: 스냅샷 100, 미집계 원장 +5·−3, 미포장 배정 10 → 92.
3. 집계기 IT: 원장 3행 추가 → 집계 1회 → `qty`·`last_tx_id` 반영. 갱신 조건 불일치 시 건너뜀.
4. 정합성 IT: 스냅샷을 직접 SQL로 훼손 → 대조 1회 → 복구, 게이지 1.
5. 조정 멱등 IT: 같은 키 두 번 → 원장 1행, 두 번째 `duplicated: true`. 같은 키 다른 delta → 409.
6. 포장 완료 IT: 잔고 0인 상품을 완료 → PACKED, 잔고 −n, 음수 게이지 1.
7. 기존 241건 통과. `ConcurrentStockIT`·`InventoryServiceIT`는 새 계산으로 기대값 수정.

## 9. 측정 (전후 비교)

- 50명 포장, 미사용 토트 목록(6,000번 이후)으로 3분 재실행. 실행 4와 같은 표: 완료 500 비율, p50/p95, HikariCP pending 최대, 데드락 수.
- 데드락 재현 테스트의 변경 전·후 결과.
- 정합성 훼손 → 지표 상승과 복구까지의 시간.
- 출고지시 접수 1,000주문 배치의 응답 시간이 변경 전(52.5초)과 같은지(가용 계산 변경의 부작용 확인).

## 10. 범위 밖

`product.stock_qty` 컬럼 삭제, 박스 재고의 원장화, 위치별 재고, 주문 취소, 토트 배정 방식 변경(실행 3 과제), 배치 접수 비동기화, 화주·채널 모델.

접수 간 재고 경합(두 배치가 같은 가용 재고를 읽고 둘 다 수용)은 현재 코드와 동일하게 남는다. 이 설계는 그 문제를 만들지도 풀지도 않는다. 배치 접수 순서 처리 과제(창고당 단일 결정자)에서 다룬다. 채널 간 순서 보장 요구는 없고, 재고 부족 시 배정 우선순위만 정책으로 둔다(기본 접수 시각 순).

## 11. 미확정

- 집계 주기 5초·대조 주기 60초·집계 지연 알람 60초는 초기값. 운영 데이터로 조정.
- 집계 지연은 정확도에 영향이 없다. 모든 조회가 미집계 원장을 더해 답하기 때문이다. 영향은 차분 쿼리 범위(정착 창 60초 + 집계 주기만큼의 행)와, `stock_balance`를 직접 읽는 외부 경로가 있을 때뿐이다(뷰로 막는다).
- 서버 2대 이상으로 갈 때의 스케줄러 구성. 인스턴스마다 `@Scheduled`를 그대로 두는 것은 표준이 아니다. 집계기·대조기는 ShedLock(같은 Postgres에 `shedlock` 테이블, `lockAtMostFor` 30초)으로 한 번에 한 인스턴스만 실행하거나, 스케줄러를 켠 워커 인스턴스 하나로 분리한다. 상관 서브쿼리 UPDATE의 이중 반영 방지는 락 만료 뒤 겹치는 경우를 위한 2차 방어로 유지한다.
- 조정 API의 권한 분리. 현재 인증이 단일 API 키라 관리자 구분이 없다. 이 설계에서는 다루지 않는다.
