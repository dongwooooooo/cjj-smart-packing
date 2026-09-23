# 원장 기반 재고 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 포장 완료 경로에서 상품 행 락을 없애고, 원장(`inventory_tx`)을 재고의 유일한 진실로 두며, 잔고 스냅샷(`stock_balance`)을 집계기·대조기로 유지한다.

**Architecture:** 재고 쓰기(입고·포장 차감·조정)는 원장 INSERT만 한다. 읽기는 `stock_balance.qty + Σ(id > last_tx_id 원장) − 미포장 배정`으로 항상 정확하다. 5초 집계기가 스냅샷을 전진시키고, 60초 대조기가 원장 전체 합과 대조해 불일치를 복구·계량한다. `product.stock_qty` 컬럼은 남기되 코드에서 완전히 떼어낸다.

**Tech Stack:** Spring Boot 4 / Spring Data JPA / JdbcTemplate / Flyway / Micrometer / Testcontainers(Postgres 18.6) / JUnit 5 / AssertJ. 스펙: `docs/superpowers/specs/2026-09-23-ledger-stock-design.md`.

## Global Constraints

- 작업 저장소는 `/Users/idong-u/d/cjj-portfolio/backend` (서브모듈). `~/cjj/backend`(팀 클론)은 절대 수정하지 않는다.
- 커밋 메시지는 한국어, `type(scope): 제목` 형식, 끝에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- 테스트 클래스는 기존 관례대로 `@SpringBootTest + @Testcontainers + @Container @ServiceConnection PostgreSQLContainer("postgres:18.6")`. 메서드 이름은 한국어.
- 테스트 실행: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "<FQCN>" -q` (Docker 필요). 전체: `./gradlew test -q`. 완료 시점 기준 기존 241건 통과 유지.
- 포장 완료는 상품 재고 부족으로 실패하지 않는다(D-L1). `OUT_OF_STOCK`은 박스 재고에만 쓴다.
- 코드에서 `product.stock_qty` 읽기·쓰기 금지(D-L3). `Product.stockQty()`·`changeStockQty()`는 Task 5에서 제거한다.
- 새 설정 키: `inventory.collector.interval-ms`(기본 5000), `inventory.reconciler.interval-ms`(기본 60000).
- 지표 이름: `inventory.collector.lag_rows`, `inventory.collector.lag_seconds`, `inventory.reconcile.mismatch`, `inventory.balance.negative`.

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `src/main/resources/db/migration/V21__stock_balance.sql` | 스냅샷 테이블·인덱스·멱등 키·뷰 |
| `src/main/java/com/awesome/backend/inventory/entity/StockBalance.java` | 스냅샷 엔티티 |
| `src/main/java/com/awesome/backend/inventory/repository/StockBalanceRepository.java` | 스냅샷 조회·실재고 계산 쿼리 |
| `src/main/java/com/awesome/backend/inventory/repository/InventoryTxRepository.java` | 멱등 키 조회 추가 |
| `src/main/java/com/awesome/backend/inventory/entity/InventoryTx.java` | `idempotencyKey`·`reason` 필드 추가 |
| `src/main/java/com/awesome/backend/inventory/service/InventoryService.java` | 원장 INSERT만, 읽기는 스냅샷+차분 |
| `src/main/java/com/awesome/backend/inventory/service/StockMovementRecorder.java` | `adjust(gtin, delta, idempotencyKey, reason)` 계약 |
| `src/main/java/com/awesome/backend/inventory/service/InventoryProperties.java` | 집계·대조 주기 설정 |
| `src/main/java/com/awesome/backend/inventory/service/StockBalanceCollector.java` | 5초 집계 + 지연 지표 |
| `src/main/java/com/awesome/backend/inventory/service/StockReconciler.java` | 60초 대조 + 복구 + 지표 |
| `src/main/java/com/awesome/backend/inventory/controller/InventoryAdjustmentController.java` 외 요청·응답 레코드 | 조정 API |
| `src/main/java/com/awesome/backend/outbound/service/ShipmentCompleteService.java` | 상품 락·검사 제거 |
| `src/main/java/com/awesome/backend/inbound/entity/Product.java` | `stockQty` 필드·메서드 제거 |
| `src/main/java/com/awesome/backend/inbound/service/StockInService.java`, `inbound/controller/ProductSummary.java`, `inbound/service/InboundScanService.java` | 실재고를 `AvailableStockQuery`로 읽음 |
| `src/main/java/com/awesome/backend/demo/service/DemoStateResetter.java`, `DemoProductProvisioner.java`, `DemoResetService.java` | 스냅샷 초기화, 직접 SQL 제거 |
| `src/test/java/com/awesome/backend/support/StockTestSupport.java` | 테스트용 재고 설정·조회 헬퍼 |
| `src/test/java/com/awesome/backend/outbound/service/ShipmentCompleteDeadlockIT.java` | 데드락 재현·회귀 |
| `src/test/java/com/awesome/backend/inventory/service/StockBalanceCollectorIT.java`, `StockReconcilerIT.java`, `InventoryAdjustmentControllerIT.java` | 신규 컴포넌트 테스트 |

---

### Task 1: 데드락 재현 테스트 (변경 전 실패 확인)

**Files:**
- Create: `src/test/java/com/awesome/backend/outbound/service/ShipmentCompleteDeadlockIT.java`
- Create: `docs/evidence/loadtest/deadlock-repro-before.txt` (cjj-portfolio 저장소 쪽, `/Users/idong-u/d/cjj-portfolio/docs/evidence/loadtest/`)

**Interfaces:**
- Consumes: `ShipmentCompleteService.complete(Long, BigDecimal)`, `StockMovementRecorder.adjust(String, int)` (현재 시그니처), V2 seed 상품 `8801234500011`(JUICE)·`8801234500028`(GRAPE), 라인 id 1, 박스 A호 id 1.
- Produces: 테스트 클래스. Task 6에서 `@Disabled`를 제거한다.

- [ ] **Step 1: 테스트 작성**

```java
package com.awesome.backend.outbound.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.awesome.backend.inventory.service.StockMovementRecorder;
import com.awesome.backend.inbound.repository.ProductRepository;
import com.awesome.backend.orders.entity.Order;
import com.awesome.backend.orders.repository.OrderRepository;
import com.awesome.backend.outbound.entity.Shipment;
import com.awesome.backend.outbound.entity.ShipmentItem;
import com.awesome.backend.outbound.entity.Tote;
import com.awesome.backend.outbound.entity.ToteAssignment;
import com.awesome.backend.outbound.repository.ShipmentItemRepository;
import com.awesome.backend.outbound.repository.ShipmentRepository;
import com.awesome.backend.outbound.repository.ToteAssignmentRepository;
import com.awesome.backend.outbound.repository.ToteRepository;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.util.ReflectionTestUtils;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 부하 테스트 실행 4(2026-09-22)의 데드락 재현. 품목 순서가 [JUICE, GRAPE]인 배송단위와
 * [GRAPE, JUICE]인 배송단위를 두 스레드가 동시에 완료한다. 상품 행을 shipment_item 순서로
 * 잠그는 현재 코드에서는 한쪽이 deadlock detected 로 끝난다. 클래스 레벨 @Transactional 없음 —
 * 스레드마다 실제 트랜잭션이 필요하다.
 */
@SpringBootTest
@Testcontainers
@Disabled("원장 기반 재고(Task 6) 적용 전에는 데드락으로 실패한다. Task 6에서 활성화")
class ShipmentCompleteDeadlockIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:18.6");

    private static final String JUICE = "8801234500011";
    private static final String GRAPE = "8801234500028";
    private static final long LINE_ID = 1L;
    private static final long BOX_A = 1L;
    private static final int ROUNDS = 20;

    @Autowired ShipmentCompleteService completeService;
    @Autowired StockMovementRecorder stockMovementRecorder;
    @Autowired ProductRepository productRepository;
    @Autowired OrderRepository orderRepository;
    @Autowired ShipmentRepository shipmentRepository;
    @Autowired ShipmentItemRepository shipmentItemRepository;
    @Autowired ToteRepository toteRepository;
    @Autowired ToteAssignmentRepository toteAssignmentRepository;

    @Test
    void 반대_순서_품목을_동시에_완료해도_둘_다_성공한다() throws Exception {
        stockMovementRecorder.adjust(JUICE, 1_000);
        stockMovementRecorder.adjust(GRAPE, 1_000);
        long juice = productRepository.findByGtin(JUICE).orElseThrow().id();
        long grape = productRepository.findByGtin(GRAPE).orElseThrow().id();

        ExecutorService pool = Executors.newFixedThreadPool(2);
        int failures = 0;
        List<String> errors = new ArrayList<>();
        for (int round = 0; round < ROUNDS; round++) {
            long a = packingShipment(List.of(juice, grape));
            long b = packingShipment(List.of(grape, juice));
            CountDownLatch start = new CountDownLatch(1);
            Future<Throwable> fa = pool.submit(() -> run(start, a));
            Future<Throwable> fb = pool.submit(() -> run(start, b));
            start.countDown();
            for (Future<Throwable> f : List.of(fa, fb)) {
                Throwable t = f.get(60, TimeUnit.SECONDS);
                if (t != null) {
                    failures++;
                    errors.add(t.getClass().getSimpleName() + ": " + firstLine(t.getMessage()));
                }
            }
        }
        pool.shutdown();
        assertThat(failures).as("실패 목록: %s", errors).isZero();
    }

    private Throwable run(CountDownLatch start, long shipmentId) {
        try {
            start.await();
            completeService.complete(shipmentId, null);
            return null;
        } catch (Throwable t) {
            return t;
        }
    }

    /** PACKING 상태 배송단위 + 품목(주어진 순서로 저장) + 유휴 토트 배정. */
    private long packingShipment(List<Long> productIds) {
        Order order = orderRepository.save(
                new Order("R-DL-" + System.nanoTime(), "SEOUL", "B-DL", LocalDateTime.now()));
        Shipment shipment = new Shipment(order.id(), 1, LINE_ID, BOX_A, false);
        ReflectionTestUtils.setField(shipment, "status", Shipment.Status.PACKING);
        shipment = shipmentRepository.save(shipment);
        for (Long productId : productIds) {
            shipmentItemRepository.save(new ShipmentItem(shipment.id(), productId, 1));
        }
        Tote tote = toteRepository.findByStatusOrderByIdAsc(Tote.Status.IDLE).stream()
                .findFirst().orElseThrow();
        tote.assign();
        toteRepository.save(tote);
        toteAssignmentRepository.save(new ToteAssignment(tote.id(), shipment.id()));
        return shipment.id();
    }

    private static String firstLine(String message) {
        return message == null ? "" : message.lines().findFirst().orElse("");
    }
}
```

- [ ] **Step 2: `@Disabled`를 잠시 주석 처리하고 실행해 현재 코드에서 실패하는 것을 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.outbound.service.ShipmentCompleteDeadlockIT" 2>&1 | tail -40`
Expected: FAIL. 단언 메시지에 `CannotAcquireLockException: ... deadlock detected`가 1건 이상. (20라운드 중 최소 1건. 0건이면 ROUNDS를 50으로 올려 재실행.)

- [ ] **Step 3: 실패 출력을 근거 파일로 저장하고 `@Disabled` 복원**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.outbound.service.ShipmentCompleteDeadlockIT" 2>&1 | grep -E "deadlock|실패 목록|FAILED|tests completed" | head -20 > /Users/idong-u/d/cjj-portfolio/docs/evidence/loadtest/deadlock-repro-before.txt
```
그 다음 Step 2에서 주석 처리한 `@Disabled`를 되돌린다.

- [ ] **Step 4: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add src/test/java/com/awesome/backend/outbound/service/ShipmentCompleteDeadlockIT.java && git commit -m "$(cat <<'EOF'
test(outbound): 포장 완료 데드락 재현 IT — 반대 순서 품목 동시 완료

원장 기반 재고 적용 전에는 deadlock detected 로 실패한다. 적용 후 활성화.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
cd /Users/idong-u/d/cjj-portfolio && git add docs/evidence/loadtest/deadlock-repro-before.txt && git commit -m "$(cat <<'EOF'
evidence(loadtest): 데드락 재현 테스트 변경 전 실패 출력

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: V21 마이그레이션 + 스냅샷 엔티티·리포지토리 + 스케줄링 활성화

**Files:**
- Create: `src/main/resources/db/migration/V21__stock_balance.sql`
- Create: `src/main/java/com/awesome/backend/inventory/entity/StockBalance.java`
- Create: `src/main/java/com/awesome/backend/inventory/repository/StockBalanceRepository.java`
- Modify: `src/main/java/com/awesome/backend/BackendApplication.java`
- Test: `src/test/java/com/awesome/backend/inventory/repository/StockBalanceRepositoryIT.java`

**Interfaces:**
- Produces: `StockBalanceRepository.onHandQty(Long productId): int` (스냅샷 + 미집계 차분, 행이 없으면 원장 전체 합), `StockBalanceRepository.findByProductId(Long): Optional<StockBalance>`, `StockBalance.qty()`, `StockBalance.lastTxId()`.

- [ ] **Step 1: 테스트 작성**

```java
package com.awesome.backend.inventory.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.awesome.backend.inbound.repository.ProductRepository;
import com.awesome.backend.inventory.entity.InventoryTx;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest
@Testcontainers
@Transactional
class StockBalanceRepositoryIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:18.6");

    private static final String CIDER = "8801234500035";

    @Autowired StockBalanceRepository stockBalanceRepository;
    @Autowired InventoryTxRepository inventoryTxRepository;
    @Autowired ProductRepository productRepository;
    @Autowired JdbcTemplate jdbcTemplate;

    @Test
    void 마이그레이션이_상품마다_스냅샷_행을_만든다() {
        Long products = jdbcTemplate.queryForObject("select count(*) from product", Long.class);
        Long balances = jdbcTemplate.queryForObject("select count(*) from stock_balance", Long.class);
        assertThat(balances).isEqualTo(products);
    }

    @Test
    void 실재고는_스냅샷에_미집계_원장을_더한_값이다() {
        Long productId = productRepository.findByGtin(CIDER).orElseThrow().id();
        jdbcTemplate.update("update stock_balance set qty = 100, last_tx_id = "
                + "(select coalesce(max(id),0) from inventory_tx where product_id = ?) where product_id = ?",
                productId, productId);
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.INBOUND, 5, "STOCK_IN", null));
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.OUTBOUND_PACKED, -3, "SHIPMENT", 1L));
        inventoryTxRepository.flush();

        assertThat(stockBalanceRepository.onHandQty(productId)).isEqualTo(102);
    }

    @Test
    void 스냅샷_행이_없는_상품은_원장_전체_합이다() {
        Long productId = productRepository.findByGtin(CIDER).orElseThrow().id();
        jdbcTemplate.update("delete from stock_balance where product_id = ?", productId);
        jdbcTemplate.update("delete from inventory_tx where product_id = ?", productId);
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.ADJUST, 7, null, null));
        inventoryTxRepository.flush();

        assertThat(stockBalanceRepository.onHandQty(productId)).isEqualTo(7);
    }

    @Test
    void 뷰는_같은_계산을_돌려준다() {
        Long productId = productRepository.findByGtin(CIDER).orElseThrow().id();
        Integer fromView = jdbcTemplate.queryForObject(
                "select on_hand_qty from v_stock_on_hand where product_id = ?", Integer.class, productId);
        assertThat(fromView).isEqualTo(stockBalanceRepository.onHandQty(productId));
    }
}
```

- [ ] **Step 2: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.repository.StockBalanceRepositoryIT" -q 2>&1 | tail -5`
Expected: 컴파일 실패 (`StockBalanceRepository` 없음).

- [ ] **Step 3: 마이그레이션 작성**

`src/main/resources/db/migration/V21__stock_balance.sql`:

```sql
-- 원장 기반 재고 (docs/superpowers/specs/2026-09-23-ledger-stock-design.md).
-- stock_balance 는 inventory_tx 를 last_tx_id 까지 집계한 스냅샷이다. 실재고는
-- 스냅샷 + (id > last_tx_id 인 원장 합) 으로 읽는다. product.stock_qty 는 남기되 쓰지 않는다.

CREATE TABLE stock_balance (
    product_id  BIGINT    PRIMARY KEY REFERENCES product (id),
    qty         INT       NOT NULL,
    last_tx_id  BIGINT    NOT NULL,
    computed_at TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO stock_balance (product_id, qty, last_tx_id)
SELECT p.id, COALESCE(SUM(t.qty_delta), 0), COALESCE(MAX(t.id), 0)
FROM product p LEFT JOIN inventory_tx t ON t.product_id = p.id
GROUP BY p.id;

DROP INDEX IF EXISTS ix_inventory_tx_product;
CREATE INDEX ix_inventory_tx_product_id ON inventory_tx (product_id, id);

ALTER TABLE inventory_tx ADD COLUMN idempotency_key VARCHAR(80);
ALTER TABLE inventory_tx ADD COLUMN reason VARCHAR(200);
CREATE UNIQUE INDEX ux_inventory_tx_idem ON inventory_tx (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE VIEW v_stock_on_hand AS
SELECT b.product_id,
       b.qty + COALESCE((SELECT SUM(t.qty_delta) FROM inventory_tx t
                         WHERE t.product_id = b.product_id AND t.id > b.last_tx_id), 0) AS on_hand_qty,
       b.last_tx_id,
       b.computed_at
FROM stock_balance b;
```

- [ ] **Step 4: 엔티티·리포지토리 작성**

`src/main/java/com/awesome/backend/inventory/entity/StockBalance.java`:

```java
package com.awesome.backend.inventory.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/** 원장(inventory_tx)을 last_tx_id 까지 집계한 잔고 스냅샷. 집계기·대조기만 쓴다. */
@Entity
@Table(name = "stock_balance")
public class StockBalance {

    @Id
    @Column(name = "product_id")
    private Long productId;

    @Column(name = "qty", nullable = false)
    private int qty;

    @Column(name = "last_tx_id", nullable = false)
    private long lastTxId;

    @Column(name = "computed_at", nullable = false)
    private LocalDateTime computedAt;

    protected StockBalance() {
    }

    public Long productId() {
        return productId;
    }

    public int qty() {
        return qty;
    }

    public long lastTxId() {
        return lastTxId;
    }

    public LocalDateTime computedAt() {
        return computedAt;
    }
}
```

`src/main/java/com/awesome/backend/inventory/repository/StockBalanceRepository.java`:

```java
package com.awesome.backend.inventory.repository;

import com.awesome.backend.inventory.entity.StockBalance;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StockBalanceRepository extends JpaRepository<StockBalance, Long> {

    Optional<StockBalance> findByProductId(Long productId);

    /**
     * 실재고 = 스냅샷 qty + (last_tx_id 이후 원장 합). 스냅샷 행이 없으면 qty 0, last_tx_id 0 으로
     * 계산해 원장 전체 합이 된다. 집계 주기와 무관하게 항상 정확하다 (D-L2).
     */
    @Query(value = """
            SELECT COALESCE((SELECT b.qty FROM stock_balance b WHERE b.product_id = :productId), 0)
                 + COALESCE((SELECT SUM(t.qty_delta) FROM inventory_tx t
                             WHERE t.product_id = :productId
                               AND t.id > COALESCE((SELECT b2.last_tx_id FROM stock_balance b2
                                                    WHERE b2.product_id = :productId), 0)), 0)
            """, nativeQuery = true)
    int onHandQty(@Param("productId") Long productId);
}
```

`src/main/java/com/awesome/backend/BackendApplication.java`:

```java
package com.awesome.backend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class BackendApplication {

    public static void main(String[] args) {
        SpringApplication.run(BackendApplication.class, args);
    }
}
```

- [ ] **Step 5: 실행해 통과 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.repository.StockBalanceRepositoryIT" -q 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL, 4 tests passed.

- [ ] **Step 6: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add src/main/resources/db/migration/V21__stock_balance.sql src/main/java/com/awesome/backend/inventory/entity/StockBalance.java src/main/java/com/awesome/backend/inventory/repository/StockBalanceRepository.java src/main/java/com/awesome/backend/BackendApplication.java src/test/java/com/awesome/backend/inventory/repository/StockBalanceRepositoryIT.java && git commit -m "$(cat <<'EOF'
feat(inventory): 잔고 스냅샷 stock_balance 테이블·뷰·실재고 계산 쿼리 (V21)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 읽기 경로를 스냅샷+차분으로 전환

**Files:**
- Modify: `src/main/java/com/awesome/backend/inventory/service/InventoryService.java`
- Modify: `src/main/java/com/awesome/backend/inventory/service/AvailableStockQuery.java` (주석만)
- Test: `src/test/java/com/awesome/backend/inventory/service/InventoryServiceIT.java`

**Interfaces:**
- Consumes: `StockBalanceRepository.onHandQty(Long)` (Task 2).
- Produces: `InventoryService.onHandQty(String gtin)`·`availableQty(String gtin)`가 원장 기준 값. 쓰기 경로는 아직 그대로(원장 + `stock_qty` 둘 다 갱신)라 두 값이 같다.

- [ ] **Step 1: 테스트 추가** — `InventoryServiceIT`에 아래 테스트를 추가한다(기존 테스트는 그대로).

```java
    @Autowired org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;

    @Test
    void 실재고와_가용재고는_스냅샷에_미집계_원장을_더해_계산한다() {
        Long productId = productRepository.findByGtin(JUICE).orElseThrow().id();
        // 스냅샷을 100 으로 고정하고, 그 뒤 원장에 +5, -3 을 넣는다.
        jdbcTemplate.update("update stock_balance set qty = 100, last_tx_id = "
                + "(select coalesce(max(id),0) from inventory_tx where product_id = ?) where product_id = ?",
                productId, productId);
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.INBOUND, 5, "STOCK_IN", null));
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.OUTBOUND_PACKED, -3, "SHIPMENT", 1L));
        inventoryTxRepository.flush();
        plannedShipment(productId, 10);

        assertThat(inventoryService.onHandQty(JUICE)).isEqualTo(102);
        assertThat(inventoryService.availableQty(JUICE)).isEqualTo(92);
    }
```

- [ ] **Step 2: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.service.InventoryServiceIT" -q 2>&1 | tail -8`
Expected: 새 테스트 FAIL (`onHandQty`가 `stock_qty`를 읽어 0 반환).

- [ ] **Step 3: `InventoryService` 읽기 경로 수정**

```java
    private final StockBalanceRepository stockBalanceRepository;

    public InventoryService(ProductRepository productRepository,
                            InventoryTxRepository inventoryTxRepository,
                            ShipmentItemRepository shipmentItemRepository,
                            StockBalanceRepository stockBalanceRepository) {
        this.productRepository = productRepository;
        this.inventoryTxRepository = inventoryTxRepository;
        this.shipmentItemRepository = shipmentItemRepository;
        this.stockBalanceRepository = stockBalanceRepository;
    }

    @Override
    @Transactional(readOnly = true)
    public int onHandQty(String gtin) {
        return stockBalanceRepository.onHandQty(product(gtin).id());
    }

    @Override
    @Transactional(readOnly = true)
    public int availableQty(String gtin) {
        Long productId = product(gtin).id();
        return stockBalanceRepository.onHandQty(productId) - shipmentItemRepository.allocatedQty(productId);
    }
```

import 추가: `com.awesome.backend.inventory.repository.StockBalanceRepository`. `AvailableStockQuery`의 `onHandQty` 주석을 `/** 실재고. 원장(inventory_tx) 스냅샷 + 미집계 차분 (D-L2). */`로 바꾼다.

- [ ] **Step 4: 실행해 통과 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.service.InventoryServiceIT" -q 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL, 5 tests passed.

- [ ] **Step 5: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add -A src/main/java/com/awesome/backend/inventory src/test/java/com/awesome/backend/inventory && git commit -m "$(cat <<'EOF'
refactor(inventory): 실재고·가용재고를 스냅샷+미집계 원장으로 계산

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 테스트 헬퍼로 재고 접근을 통일 (동작 변화 없음)

기존 테스트 12개 파일이 `product.stockQty()`, `changeStockQty`, `update product set stock_qty` 로 재고를 읽고 쓴다. Task 5에서 `stock_qty`를 떼어내기 전에, 전부 원장 경유 헬퍼로 바꿔 스위트를 그대로 통과시킨다.

**Files:**
- Create: `src/test/java/com/awesome/backend/support/StockTestSupport.java`
- Modify: 아래 목록의 테스트 파일

| 파일 | 바꿀 것 |
| --- | --- |
| `outbound/controller/ShipmentCompleteControllerIT.java` | `setStock` 본문 → 헬퍼, `product.stockQty()` 단언 12곳 → `stock.onHand(gtin)` |
| `outbound/controller/OutboundFlowE2EIT.java` | `stockQty()` 6곳, `stock_qty` SQL 1곳 |
| `inbound/controller/StockInControllerIT.java` | `stockQty()` 3곳, `stock_qty` SQL 1곳 |
| `inbound/controller/MeasurementConfirmIT.java`, `MeasurementControllerIT.java` | `stockQty()` 각 2곳 (before/after 비교) |
| `outbound/controller/BoxTypeControllerIT.java` | `stockQty()` 2곳 — **박스** 재고면 그대로 둔다. 상품이면 헬퍼 |
| `demo/controller/DemoResetIT.java` | `stockQty()` 4곳, `stock_qty` SQL 3곳 |
| `demo/controller/DemoResetSequenceIT.java`, `DemoAutoIT.java`, `orders/controller/OrdersImportToteShortageIT.java` | `stock_qty` SQL |
| `demo/service/DemoSampleDataTest.java`, `DemoDataLoaderTest.java` | `spec.stockQty()`(DemoProductSpec 필드)면 그대로. `product.stockQty()`면 헬퍼 |

**Interfaces:**
- Produces: `StockTestSupport.set(String gtin, int qty)` (원장 조정으로 실재고를 정확히 qty 로 맞춤), `StockTestSupport.onHand(String gtin): int`, `StockTestSupport.setByProductId(Long, int)`, `onHandByProductId(Long)`.

- [ ] **Step 1: 헬퍼 작성**

```java
package com.awesome.backend.support;

import com.awesome.backend.inbound.repository.ProductRepository;
import com.awesome.backend.inventory.service.AvailableStockQuery;
import com.awesome.backend.inventory.service.StockMovementRecorder;
import org.springframework.boot.test.context.TestComponent;

/**
 * 테스트용 재고 설정·조회. product.stock_qty 를 직접 만지지 않고 원장 창구만 쓴다 —
 * 원장 기반 재고(D-L3)에서는 컬럼을 읽지 않기 때문이다.
 */
@TestComponent
public class StockTestSupport {

    private final StockMovementRecorder recorder;
    private final AvailableStockQuery query;
    private final ProductRepository productRepository;

    public StockTestSupport(StockMovementRecorder recorder, AvailableStockQuery query,
                            ProductRepository productRepository) {
        this.recorder = recorder;
        this.query = query;
        this.productRepository = productRepository;
    }

    /** 실재고를 정확히 qty 로 맞춘다 (차이만큼 조정 원장 추가). */
    public void set(String gtin, int qty) {
        int delta = qty - query.onHandQty(gtin);
        if (delta != 0) {
            recorder.adjust(gtin, delta);
        }
    }

    public int onHand(String gtin) {
        return query.onHandQty(gtin);
    }

    public void setByProductId(Long productId, int qty) {
        set(gtinOf(productId), qty);
    }

    public int onHandByProductId(Long productId) {
        return onHand(gtinOf(productId));
    }

    private String gtinOf(Long productId) {
        return productRepository.findGtinById(productId).orElseThrow();
    }
}
```

`@TestComponent`는 컴포넌트 스캔에서 제외되므로 각 테스트 클래스에 `@Import(StockTestSupport.class)`를 붙이고 `@Autowired StockTestSupport stock;`로 받는다.

- [ ] **Step 2: 파일별 치환**

각 파일에서 다음 규칙으로 바꾼다. 치환 후 `grep -rn "stockQty()\|changeStockQty\|stock_qty" src/test/java`에 남는 것은 `DemoProductSpec.stockQty()`·`BoxType.stockQty()`·`box_type ... stock_qty` 뿐이어야 한다.

| 기존 | 변경 |
| --- | --- |
| `product.changeStockQty(qty); productRepository.save(product);` | `stock.set(gtin, qty);` |
| `productRepository.findByGtin(G).orElseThrow().stockQty()` | `stock.onHand(G)` |
| `productRepository.findById(id).orElseThrow().stockQty()` | `stock.onHandByProductId(id)` |
| `jdbcTemplate.update("update product set stock_qty = ? where gtin = ?", n, g)` | `stock.set(g, n)` |
| `jdbcTemplate.update("update product set stock_qty = 0 ...")` (전체) | 해당 gtin 들에 대해 `stock.set(g, 0)` 반복. gtin 목록이 코드에 없으면 `productRepository.findAll()`로 돌며 `stock.set(p.gtin(), 0)` |
| `assertThat(product.stockQty()).isZero()` | `assertThat(stock.onHand(product.gtin())).isZero()` |

`ShipmentCompleteControllerIT.setStock` 은 본문을 `stock.set(gtin, qty);` 한 줄로 바꾼다(호출부는 그대로).

- [ ] **Step 3: 전체 테스트 실행**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test -q 2>&1 | tail -15`
Expected: BUILD SUCCESSFUL. 실패 0 (데드락 IT는 `@Disabled`).

- [ ] **Step 4: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add -A src/test/java && git commit -m "$(cat <<'EOF'
test: 재고 설정·조회를 StockTestSupport(원장 경유)로 통일

product.stock_qty 직접 읽기·쓰기를 테스트에서 제거한다. 동작 변화 없음.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 쓰기 경로를 원장 INSERT만으로, `Product.stockQty` 제거

**Files:**
- Modify: `src/main/java/com/awesome/backend/inventory/service/InventoryService.java`
- Modify: `src/main/java/com/awesome/backend/inventory/service/StockMovementRecorder.java` (주석)
- Modify: `src/main/java/com/awesome/backend/inbound/entity/Product.java`
- Modify: `src/main/java/com/awesome/backend/inbound/service/StockInService.java`
- Modify: `src/main/java/com/awesome/backend/inbound/controller/ProductSummary.java`
- Modify: `src/main/java/com/awesome/backend/inbound/service/InboundScanService.java`
- Modify: `src/main/java/com/awesome/backend/demo/service/DemoResetService.java`, `DemoProductProvisioner.java`
- Test: `src/test/java/com/awesome/backend/inventory/service/InventoryServiceIT.java`, `ConcurrentStockIT.java`

**Interfaces:**
- Consumes: `AvailableStockQuery.onHandQty(String)`.
- Produces: `StockMovementRecorder.recordOutboundPacked`가 재고 부족을 던지지 않는다(D-L1). `ProductSummary.from(Product, Category, String imageUrl, int onHandQty)`.

- [ ] **Step 1: 테스트 수정** — `InventoryServiceIT`에서 `재고보다_많은_차감은_거부한다`를 아래로 교체한다.

```java
    @Test
    void 재고보다_많은_차감도_기록하고_실재고는_음수가_된다() {
        inventoryService.recordInbound(JUICE, 3);
        inventoryService.recordOutboundPacked(JUICE, 5, 1L);
        assertThat(inventoryService.onHandQty(JUICE)).isEqualTo(-2);
    }

    @Test
    void 쓰기_경로는_원장만_추가하고_상품_행을_갱신하지_않는다() {
        Long productId = productRepository.findByGtin(JUICE).orElseThrow().id();
        java.time.LocalDateTime before = jdbcTemplate.queryForObject(
                "select updated_at from product where id = ?", java.time.LocalDateTime.class, productId);
        inventoryService.recordInbound(JUICE, 10);
        inventoryService.recordOutboundPacked(JUICE, 4, 1L);
        inventoryService.adjust(JUICE, -1);
        inventoryTxRepository.flush();
        java.time.LocalDateTime after = jdbcTemplate.queryForObject(
                "select updated_at from product where id = ?", java.time.LocalDateTime.class, productId);
        assertThat(after).isEqualTo(before);
        assertThat(inventoryService.onHandQty(JUICE)).isEqualTo(5);
    }
```

기존 테스트 이름의 "캐시"를 "원장"으로 바꾼다(`수량_입고는_장부_기록과_캐시_증가를_함께_한다` → `수량_입고는_원장에_기록되고_실재고에_반영된다`, `포장완료_차감은_장부와_캐시를_함께_줄인다` → `포장완료_차감은_원장에_기록되고_실재고를_줄인다`). 본문은 그대로.

`ConcurrentStockIT`의 원복 줄 `inventoryService.adjust(RAMEN, -THREADS);`는 Task 9에서 시그니처가 바뀌므로 지금은 그대로 둔다.

- [ ] **Step 2: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.service.InventoryServiceIT" -q 2>&1 | tail -8`
Expected: `재고보다_많은_차감도_기록하고...` FAIL (OUT_OF_STOCK 예외), `쓰기_경로는_원장만...` FAIL (updated_at 변경 — `changeStockQty`가 엔티티를 더티로 만들어 `updated_at`이 갱신됨. 만약 `updated_at`이 JPA 에서 자동 갱신되지 않아 이 단언이 통과하면, 대신 `select stock_qty from product`가 변하지 않는 것을 단언한다).

- [ ] **Step 3: `InventoryService` 쓰기 경로 수정**

```java
    @Override
    public void recordInbound(String gtin, int qty) {
        inventoryTxRepository.save(
                new InventoryTx(product(gtin).id(), InventoryTx.TxType.INBOUND, qty, "STOCK_IN", null));
    }

    /** 포장 완료는 실물이 나갔다는 사실의 기록이다. 부족해도 막지 않는다 — 음수 잔고는 대조기가 보고한다 (D-L1). */
    @Override
    public void recordOutboundPacked(String gtin, int qty, long shipmentId) {
        inventoryTxRepository.save(
                new InventoryTx(product(gtin).id(), InventoryTx.TxType.OUTBOUND_PACKED, -qty, "SHIPMENT", shipmentId));
    }

    @Override
    public void adjust(String gtin, int delta) {
        inventoryTxRepository.save(
                new InventoryTx(product(gtin).id(), InventoryTx.TxType.ADJUST, delta, null, null));
    }
```

`productForUpdate` 메서드와 `ApiException`·`ErrorCode`·`Map` import 중 안 쓰는 것을 지운다(`notFound`는 남는다). 클래스 주석을 `재고 이동·조회 구현. 쓰기는 원장(inventory_tx) 추가만, 읽기는 스냅샷+미집계 차분 (specs/2026-09-23-ledger-stock-design.md).`로 바꾼다.

`StockMovementRecorder.recordOutboundPacked` 주석을 `/** 포장완료 차감 (P2). 부족해도 기록한다 — 잔고가 음수가 되면 정합성 대조기가 지표로 보고한다 (D-L1). */`로 바꾼다.

- [ ] **Step 4: `Product`에서 `stockQty` 제거**

`Product.java`에서 필드 `@Column(name = "stock_qty", nullable = false) private int stockQty;`, 메서드 `stockQty()`, `changeStockQty(int)`와 클래스 주석의 "재고 캐시(stock_qty)까지만 담았다 … 단일 창구로만 한다" 두 문장을 지운다. DB 컬럼은 `DEFAULT 0`이라 INSERT 에 빠져도 된다.

- [ ] **Step 5: 컴파일 오류가 나는 호출처를 고친다**

`StockInService`:
```java
    private final AvailableStockQuery stockQuery;

    public StockInService(ProductRepository productRepository,
                          StockMovementRecorder stockMovementRecorder,
                          AvailableStockQuery stockQuery) {
        this.productRepository = productRepository;
        this.stockMovementRecorder = stockMovementRecorder;
        this.stockQuery = stockQuery;
    }

    @Transactional
    public StockInResponse stockIn(Long productId, int qty) {
        String gtin = productRepository.findGtinById(productId)
                .orElseThrow(() -> new ApiException(ErrorCode.PRODUCT_NOT_FOUND,
                        "상품을 찾을 수 없습니다.", Map.of("productId", productId)));
        stockMovementRecorder.recordInbound(gtin, qty);
        return new StockInResponse(productId, stockQuery.onHandQty(gtin));
    }
```
클래스 주석의 "장부 기록과 캐시 갱신이 한 트랜잭션으로 묶여야" 문장을 "재고는 원장 창구로만 바뀐다"로 바꾼다. `ProductRepository#findGtinById` 관련 주석 2줄은 지운다.

`ProductSummary`:
```java
    public static ProductSummary from(Product product, Category category, String imageUrl, int onHandQty) {
        return new ProductSummary(
                product.id(), product.gtin(), product.name(),
                category.getLargeName(), category.getName(),
                imageUrl, product.dimStatus(), onHandQty);
    }
```
두 인자·세 인자 `from` 오버로드는 지우고, 호출처(`InboundScanService` 2곳, 그 외 `grep -rn "ProductSummary.from" src/main`)에 `stockQuery.onHandQty(product.gtin())`를 넘긴다. `InboundScanService`에 `AvailableStockQuery` 생성자 주입을 추가한다.

`DemoResetService.status()`의 `product.stockQty()` → `stockQuery.onHandQty(product.gtin())` (`AvailableStockQuery` 주입 추가).

`DemoProductProvisioner.alignStock`:
```java
    private void alignStock(DemoProductSpec spec) {
        int delta = spec.stockQty() - stockQuery.onHandQty(spec.gtin());
        if (delta != 0) {
            inventoryService.adjust(spec.gtin(), delta);
        }
    }
```
`pruneDropped`의 `update product set stock_qty = 0 ...` 두 SQL 은 삭제하고, 대신 삭제 대상 gtin 을 먼저 조회해 각각 `inventoryService.adjust(gtin, -stockQuery.onHandQty(gtin))`를 호출한다(실재고가 0 이 아니면). `provision` 의 INSERT SQL 에서 `stock_qty` 컬럼과 값을 뺀다. `AvailableStockQuery stockQuery` 생성자 주입 추가.

- [ ] **Step 6: 전체 테스트**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test -q 2>&1 | tail -15`
Expected: BUILD SUCCESSFUL. `ShipmentCompleteControllerIT.상품_재고_부족이면_409_OUT_OF_STOCK…`가 실패하면 Task 6에서 다룰 것이므로 그 1건만 허용. 그 외 실패는 이 태스크에서 고친다.

- [ ] **Step 7: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add -A src/main src/test && git commit -m "$(cat <<'EOF'
refactor(inventory): 재고 쓰기를 원장 추가만으로, Product.stockQty 제거

- 입고·포장 차감·조정이 상품 행을 잠그지 않는다
- 포장 차감은 부족해도 기록한다(D-L1) — 음수 잔고는 대조기가 보고
- 실재고 읽기는 전부 AvailableStockQuery.onHandQty 경유

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: 포장 완료에서 상품 조회·락·검사 제거, 데드락 IT 활성화

**Files:**
- Modify: `src/main/java/com/awesome/backend/outbound/service/ShipmentCompleteService.java`
- Modify: `src/test/java/com/awesome/backend/outbound/controller/ShipmentCompleteControllerIT.java`
- Modify: `src/test/java/com/awesome/backend/outbound/service/ShipmentCompleteDeadlockIT.java`

**Interfaces:**
- Consumes: `StockMovementRecorder.recordOutboundPacked(String gtin, int qty, long shipmentId)`, `ProductRepository.findGtinById(Long)`.

- [ ] **Step 1: 컨트롤러 IT의 상품 재고 부족 테스트를 D-L1 에 맞게 교체**

`상품_재고_부족이면_409_OUT_OF_STOCK이고_앞선_항목_반영도_롤백된다`(168행 근처)를 지우고 아래로 바꾼다. 픽스처 코드(CHIP·GRAPE 두 품목 배송단위 준비)는 기존 것을 그대로 쓴다.

```java
    @Test
    void 상품_재고가_부족해도_완료되고_실재고는_음수가_된다() throws IOException, InterruptedException {
        Line line = lineRepository.findAll().get(0);
        setStock(CHIP, 1);
        setStock(GRAPE, 0);
        long chipId = productRepository.findByGtin(CHIP).orElseThrow().id();
        long grapeId = productRepository.findByGtin(GRAPE).orElseThrow().id();
        Shipment shipment = savePackingShipment(line, BOX_A, null);
        shipmentItemRepository.save(new ShipmentItem(shipment.id(), chipId, 1));
        shipmentItemRepository.save(new ShipmentItem(shipment.id(), grapeId, 2));
        assignIdleTote(shipment.id());

        HttpResponse<String> response = post("/api/v1/shipments/" + shipment.id() + "/complete");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(stock.onHand(CHIP)).isZero();
        assertThat(stock.onHand(GRAPE)).isEqualTo(-2);
        assertThat(shipmentRepository.findById(shipment.id()).orElseThrow().status())
                .isEqualTo(Shipment.Status.PACKED);
    }
```

박스 재고 부족 테스트(`박스_재고_부족이면_409_OUT_OF_STOCK이고_이미_반영한_상품…`)는 그대로 둔다. 단, 그 테스트가 "상품 원장이 롤백됐다"를 `stock.onHand`로 단언한다면 그 단언은 유효하다(트랜잭션 롤백).

- [ ] **Step 2: 데드락 IT 활성화** — `ShipmentCompleteDeadlockIT`에서 `@Disabled(...)` 줄과 `import org.junit.jupiter.api.Disabled;`를 지운다.

- [ ] **Step 3: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.outbound.service.ShipmentCompleteDeadlockIT" -q 2>&1 | tail -8`
Expected: FAIL — 아직 `ShipmentCompleteService`가 `productRepository.findById` 뒤 `recordOutboundPacked`를 부르는데, Task 5 이후 `recordOutboundPacked`는 락을 안 잡으므로 데드락은 사라졌을 수 있다. 통과하면 그대로 Step 4로 간다(락이 사라진 것이 곧 목표). 실패하면 원인을 `deadlock` 문자열로 확인한다.

- [ ] **Step 4: `ShipmentCompleteService` 정리**

`complete` 안의 4단계를 아래로 바꾼다.

```java
        // 4. 상품 재고 차감 — 원장 기록만. 상품 행을 읽거나 잠그지 않는다(D-L1, D-L3).
        //    부족해도 막지 않는다. 포장 완료는 실물이 나갔다는 사실의 기록이고, 수용 판단은
        //    출고지시 접수의 소프트 배정이 했다. 음수 잔고는 정합성 대조기가 지표로 올린다.
        for (ShipmentItem item : shipmentItemRepository.findByShipmentId(shipmentId)) {
            String gtin = productRepository.findGtinById(item.productId())
                    .orElseThrow(() -> new ApiException(ErrorCode.INTERNAL_ERROR,
                            "shipment_item이 참조하는 상품을 찾을 수 없습니다: productId=" + item.productId()));
            stockMovementRecorder.recordOutboundPacked(gtin, item.qty(), shipmentId);
        }
```

`import com.awesome.backend.inbound.entity.Product;`를 지운다. 클래스 주석의 "(예: 세 번째 상품에서 재고 부족)"를 "(예: 박스 재고 부족)"으로, "상품 재고 차감(N건)"은 그대로 둔다. 박스 락 주석(5단계)에 한 줄을 더한다: `이 트랜잭션이 잡는 행 락은 박스 한 행뿐이라 다른 완료와 순환 대기가 생기지 않는다.`

- [ ] **Step 5: 실행해 통과 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.outbound.service.ShipmentCompleteDeadlockIT" --tests "com.awesome.backend.outbound.controller.ShipmentCompleteControllerIT" -q 2>&1 | tail -8`
Expected: BUILD SUCCESSFUL. 데드락 IT 20라운드 실패 0.

- [ ] **Step 6: 변경 후 출력을 근거로 저장**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.outbound.service.ShipmentCompleteDeadlockIT" 2>&1 | grep -E "ShipmentCompleteDeadlockIT|PASSED|FAILED|tests completed|BUILD" | head -10 > /Users/idong-u/d/cjj-portfolio/docs/evidence/loadtest/deadlock-repro-after.txt
```

- [ ] **Step 7: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add -A src/main/java/com/awesome/backend/outbound src/test/java/com/awesome/backend/outbound && git commit -m "$(cat <<'EOF'
fix(outbound): 포장 완료에서 상품 행 락·재고 부족 검사 제거 — 데드락 원인 제거

트랜잭션이 잡는 행 락이 박스 한 행뿐이라 완료끼리 순환 대기가 없다.
데드락 재현 IT 활성화(20라운드 실패 0).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
cd /Users/idong-u/d/cjj-portfolio && git add docs/evidence/loadtest/deadlock-repro-after.txt && git commit -m "$(cat <<'EOF'
evidence(loadtest): 데드락 재현 테스트 변경 후 통과 출력

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: 집계기 `StockBalanceCollector` + 지연 지표

**Files:**
- Create: `src/main/java/com/awesome/backend/inventory/service/InventoryProperties.java`
- Create: `src/main/java/com/awesome/backend/inventory/service/StockBalanceCollector.java`
- Modify: `src/main/java/com/awesome/backend/inventory/service/InventoryConfig.java` (`@EnableConfigurationProperties`)
- Modify: `src/main/resources/application.yml`
- Test: `src/test/java/com/awesome/backend/inventory/service/StockBalanceCollectorIT.java`

**Interfaces:**
- Produces: `StockBalanceCollector.collectOnce(): int` (갱신한 상품 수, 스케줄러와 테스트가 같이 호출), 게이지 `inventory.collector.lag_rows`, `inventory.collector.lag_seconds`.

- [ ] **Step 1: 테스트 작성**

```java
package com.awesome.backend.inventory.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.awesome.backend.inbound.repository.ProductRepository;
import com.awesome.backend.inventory.entity.InventoryTx;
import com.awesome.backend.inventory.entity.StockBalance;
import com.awesome.backend.inventory.repository.InventoryTxRepository;
import com.awesome.backend.inventory.repository.StockBalanceRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 클래스 레벨 @Transactional 없음 — 집계기는 커밋된 원장만 봐야 한다. */
@SpringBootTest(properties = "inventory.collector.interval-ms=3600000")
@Testcontainers
class StockBalanceCollectorIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:18.6");

    private static final String PIE = "8801234500059";

    @Autowired StockBalanceCollector collector;
    @Autowired StockBalanceRepository stockBalanceRepository;
    @Autowired InventoryTxRepository inventoryTxRepository;
    @Autowired ProductRepository productRepository;
    @Autowired MeterRegistry registry;
    @Autowired JdbcTemplate jdbcTemplate;

    @Test
    void 미집계_원장을_스냅샷에_더하고_last_tx_id를_전진시킨다() {
        Long productId = productRepository.findByGtin(PIE).orElseThrow().id();
        collector.collectOnce();
        StockBalance before = stockBalanceRepository.findByProductId(productId).orElseThrow();

        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.INBOUND, 10, "STOCK_IN", null));
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.OUTBOUND_PACKED, -4, "SHIPMENT", 1L));
        InventoryTx last = inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.ADJUST, 1, null, null));

        int updated = collector.collectOnce();
        StockBalance after = stockBalanceRepository.findByProductId(productId).orElseThrow();

        assertThat(updated).isGreaterThanOrEqualTo(1);
        assertThat(after.qty()).isEqualTo(before.qty() + 7);
        assertThat(after.lastTxId()).isEqualTo(idOf(last));
        assertThat(registry.get("inventory.collector.lag_rows").gauge().value()).isZero();
    }

    @Test
    void 스냅샷_행이_없는_상품은_집계_때_행이_생긴다() {
        Long productId = productRepository.findByGtin(PIE).orElseThrow().id();
        jdbcTemplate.update("delete from stock_balance where product_id = ?", productId);
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.ADJUST, 3, null, null));

        collector.collectOnce();

        StockBalance created = stockBalanceRepository.findByProductId(productId).orElseThrow();
        Integer ledgerTotal = jdbcTemplate.queryForObject(
                "select coalesce(sum(qty_delta),0) from inventory_tx where product_id = ?", Integer.class, productId);
        assertThat(created.qty()).isEqualTo(ledgerTotal);
    }

    @Test
    void 두_번_연속_집계해도_이중_반영되지_않는다() {
        Long productId = productRepository.findByGtin(PIE).orElseThrow().id();
        collector.collectOnce();
        int base = stockBalanceRepository.findByProductId(productId).orElseThrow().qty();
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.ADJUST, 5, null, null));

        collector.collectOnce();
        collector.collectOnce();

        assertThat(stockBalanceRepository.findByProductId(productId).orElseThrow().qty()).isEqualTo(base + 5);
    }

    private long idOf(InventoryTx tx) {
        return jdbcTemplate.queryForObject("select max(id) from inventory_tx", Long.class);
    }
}
```

- [ ] **Step 2: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.service.StockBalanceCollectorIT" -q 2>&1 | tail -5`
Expected: 컴파일 실패 (`StockBalanceCollector` 없음).

- [ ] **Step 3: 설정·집계기 작성**

`InventoryProperties.java`:
```java
package com.awesome.backend.inventory.service;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * 원장 기반 재고의 스케줄 주기 (specs/2026-09-23-ledger-stock-design.md D-L5).
 *
 * @param collector  스냅샷 집계기. 기본 5초 — 시연 화면 새로고침 주기와 같다
 * @param reconciler 정합성 대조기. 기본 60초 — 상품별 원장 전체 합 쿼리 비용을 고려한 값
 */
@ConfigurationProperties(prefix = "inventory")
public record InventoryProperties(@DefaultValue Collector collector, @DefaultValue Reconciler reconciler) {

    public record Collector(@DefaultValue("5000") long intervalMs) {
    }

    public record Reconciler(@DefaultValue("60000") long intervalMs) {
    }
}
```

`InventoryConfig.java`에 `@EnableConfigurationProperties(InventoryProperties.class)`를 붙인다(import `org.springframework.boot.context.properties.EnableConfigurationProperties`).

`application.yml`의 `packing:` 블록 앞에 추가:
```yaml
inventory:
  # 원장 기반 재고 (specs/2026-09-23-ledger-stock-design.md). 두 값 다 초기값, 운영에서 조정.
  collector:
    interval-ms: 5000
  reconciler:
    interval-ms: 60000
```

`StockBalanceCollector.java`:
```java
package com.awesome.backend.inventory.service;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 잔고 스냅샷 집계기. last_tx_id 이후 원장을 상품별로 합쳐 stock_balance 에 더한다.
 *
 * <p>UPDATE 의 WHERE 에 {@code b.last_tx_id < d.max_id} 를 두어, 인스턴스 둘이 같은 구간을
 * 동시에 집계해도 두 번째는 갱신되지 않는다(첫 번째가 last_tx_id 를 전진시킨 뒤 재평가).
 */
@Component
public class StockBalanceCollector {

    private static final Logger log = LoggerFactory.getLogger(StockBalanceCollector.class);

    private static final String INSERT_MISSING = """
            INSERT INTO stock_balance (product_id, qty, last_tx_id)
            SELECT p.id, 0, 0 FROM product p
            WHERE NOT EXISTS (SELECT 1 FROM stock_balance b WHERE b.product_id = p.id)
            """;

    private static final String ADVANCE = """
            WITH d AS (
                SELECT t.product_id, SUM(t.qty_delta) AS delta, MAX(t.id) AS max_id
                FROM inventory_tx t JOIN stock_balance b ON b.product_id = t.product_id
                WHERE t.id > b.last_tx_id
                GROUP BY t.product_id)
            UPDATE stock_balance b
               SET qty = b.qty + d.delta, last_tx_id = d.max_id, computed_at = now()
              FROM d
             WHERE b.product_id = d.product_id AND b.last_tx_id < d.max_id
            """;

    private static final String LAG = """
            SELECT COUNT(*) AS rows, MIN(t.created_at) AS oldest
              FROM inventory_tx t JOIN stock_balance b ON b.product_id = t.product_id
             WHERE t.id > b.last_tx_id
            """;

    private final JdbcTemplate jdbcTemplate;
    private final AtomicLong lagRows = new AtomicLong();
    private final AtomicLong lagSeconds = new AtomicLong();

    public StockBalanceCollector(JdbcTemplate jdbcTemplate, MeterRegistry registry) {
        this.jdbcTemplate = jdbcTemplate;
        Gauge.builder("inventory.collector.lag_rows", lagRows, AtomicLong::get)
                .description("아직 스냅샷에 더해지지 않은 원장 행 수").register(registry);
        Gauge.builder("inventory.collector.lag_seconds", lagSeconds, AtomicLong::get)
                .description("가장 오래된 미집계 원장 행의 나이(초)").register(registry);
    }

    @Scheduled(fixedDelayString = "${inventory.collector.interval-ms:5000}")
    public void collect() {
        try {
            collectOnce();
        } catch (RuntimeException e) {
            log.warn("stock balance collect failed", e);
        }
    }

    /** 한 번 집계한다. 갱신한 상품 수를 돌려준다. */
    @Transactional
    public int collectOnce() {
        jdbcTemplate.update(INSERT_MISSING);
        int updated = jdbcTemplate.update(ADVANCE);
        Map<String, Object> lag = jdbcTemplate.queryForMap(LAG);
        lagRows.set(((Number) lag.get("rows")).longValue());
        Object oldest = lag.get("oldest");
        lagSeconds.set(oldest == null ? 0
                : ChronoUnit.SECONDS.between(((java.sql.Timestamp) oldest).toLocalDateTime(), LocalDateTime.now()));
        return updated;
    }
}
```

- [ ] **Step 4: 실행해 통과 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.service.StockBalanceCollectorIT" -q 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL, 3 tests passed.

- [ ] **Step 5: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add -A src/main/java/com/awesome/backend/inventory src/main/resources/application.yml src/test/java/com/awesome/backend/inventory && git commit -m "$(cat <<'EOF'
feat(inventory): 잔고 스냅샷 집계기 — 5초 주기, 미집계 행·지연 초 지표

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: 대조기 `StockReconciler` + 복구 + 지표

**Files:**
- Create: `src/main/java/com/awesome/backend/inventory/service/StockReconciler.java`
- Test: `src/test/java/com/awesome/backend/inventory/service/StockReconcilerIT.java`

**Interfaces:**
- Produces: `StockReconciler.reconcileOnce(): int` (복구한 상품 수), 게이지 `inventory.reconcile.mismatch`, `inventory.balance.negative`.

- [ ] **Step 1: 테스트 작성**

```java
package com.awesome.backend.inventory.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.awesome.backend.inbound.repository.ProductRepository;
import com.awesome.backend.inventory.entity.InventoryTx;
import com.awesome.backend.inventory.repository.InventoryTxRepository;
import com.awesome.backend.inventory.repository.StockBalanceRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(properties = {
        "inventory.collector.interval-ms=3600000",
        "inventory.reconciler.interval-ms=3600000"})
@Testcontainers
class StockReconcilerIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:18.6");

    private static final String GRAPE = "8801234500028";

    @Autowired StockReconciler reconciler;
    @Autowired StockBalanceCollector collector;
    @Autowired StockBalanceRepository stockBalanceRepository;
    @Autowired InventoryTxRepository inventoryTxRepository;
    @Autowired ProductRepository productRepository;
    @Autowired MeterRegistry registry;
    @Autowired JdbcTemplate jdbcTemplate;

    @Test
    void 훼손된_스냅샷을_원장_기준으로_복구하고_불일치를_센다() {
        Long productId = productRepository.findByGtin(GRAPE).orElseThrow().id();
        collector.collectOnce();
        Integer ledgerTotal = jdbcTemplate.queryForObject(
                "select coalesce(sum(qty_delta),0) from inventory_tx where product_id = ?", Integer.class, productId);
        jdbcTemplate.update("update stock_balance set qty = qty + 999 where product_id = ?", productId);

        int fixed = reconciler.reconcileOnce();

        assertThat(fixed).isEqualTo(1);
        assertThat(stockBalanceRepository.onHandQty(productId)).isEqualTo(ledgerTotal);
        assertThat(registry.get("inventory.reconcile.mismatch").gauge().value()).isEqualTo(1.0);
    }

    @Test
    void 일치하면_아무것도_바꾸지_않고_불일치_0이다() {
        collector.collectOnce();
        int fixed = reconciler.reconcileOnce();
        assertThat(fixed).isZero();
        assertThat(registry.get("inventory.reconcile.mismatch").gauge().value()).isZero();
    }

    @Test
    void 음수_잔고_상품_수를_센다() {
        Long productId = productRepository.findByGtin(GRAPE).orElseThrow().id();
        int onHand = stockBalanceRepository.onHandQty(productId);
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.OUTBOUND_PACKED, -(onHand + 1), "SHIPMENT", 1L));

        reconciler.reconcileOnce();

        assertThat(registry.get("inventory.balance.negative").gauge().value()).isGreaterThanOrEqualTo(1.0);
        inventoryTxRepository.save(new InventoryTx(productId, InventoryTx.TxType.ADJUST, onHand + 1, null, null)); // 원복
    }
}
```

- [ ] **Step 2: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.service.StockReconcilerIT" -q 2>&1 | tail -5`
Expected: 컴파일 실패 (`StockReconciler` 없음).

- [ ] **Step 3: 대조기 작성**

```java
package com.awesome.backend.inventory.service;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 정합성 대조기. 상품별 원장 전체 합과 (스냅샷 + 미집계 차분)을 대조한다. 스냅샷은 원장에서
 * 유도한 값이라 어긋남의 원인은 코드 버그나 직접 SQL 뿐이고, 원장을 진실로 두고 스냅샷을
 * 다시 만드는 것이 안전하다 (D-L6). 원장은 고치지 않는다.
 */
@Component
public class StockReconciler {

    private static final Logger log = LoggerFactory.getLogger(StockReconciler.class);

    private static final String MISMATCHES = """
            SELECT b.product_id,
                   b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0) AS derived,
                   COALESCE(SUM(t.qty_delta), 0) AS ledger_total
              FROM stock_balance b LEFT JOIN inventory_tx t ON t.product_id = b.product_id
             GROUP BY b.product_id, b.qty, b.last_tx_id
            HAVING b.qty + COALESCE(SUM(t.qty_delta) FILTER (WHERE t.id > b.last_tx_id), 0)
                <> COALESCE(SUM(t.qty_delta), 0)
            """;

    private static final String REBUILD = """
            UPDATE stock_balance
               SET qty = (SELECT COALESCE(SUM(qty_delta), 0) FROM inventory_tx WHERE product_id = ?),
                   last_tx_id = (SELECT COALESCE(MAX(id), 0) FROM inventory_tx WHERE product_id = ?),
                   computed_at = now()
             WHERE product_id = ?
            """;

    private static final String NEGATIVE = "SELECT COUNT(*) FROM v_stock_on_hand WHERE on_hand_qty < 0";

    private final JdbcTemplate jdbcTemplate;
    private final AtomicLong mismatch = new AtomicLong();
    private final AtomicLong negative = new AtomicLong();

    public StockReconciler(JdbcTemplate jdbcTemplate, MeterRegistry registry) {
        this.jdbcTemplate = jdbcTemplate;
        Gauge.builder("inventory.reconcile.mismatch", mismatch, AtomicLong::get)
                .description("마지막 대조에서 원장과 어긋나 복구한 상품 수").register(registry);
        Gauge.builder("inventory.balance.negative", negative, AtomicLong::get)
                .description("실재고가 음수인 상품 수 — 실물과 장부가 어긋났다는 신호").register(registry);
    }

    @Scheduled(fixedDelayString = "${inventory.reconciler.interval-ms:60000}")
    public void reconcile() {
        try {
            reconcileOnce();
        } catch (RuntimeException e) {
            log.warn("stock reconcile failed", e);
        }
    }

    /** 한 번 대조한다. 복구한 상품 수를 돌려준다. */
    @Transactional
    public int reconcileOnce() {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(MISMATCHES);
        for (Map<String, Object> row : rows) {
            long productId = ((Number) row.get("product_id")).longValue();
            log.warn("stock balance mismatch productId={} derived={} ledgerTotal={} -> rebuilt from ledger",
                    productId, row.get("derived"), row.get("ledger_total"));
            jdbcTemplate.update(REBUILD, productId, productId, productId);
        }
        mismatch.set(rows.size());
        Long negatives = jdbcTemplate.queryForObject(NEGATIVE, Long.class);
        negative.set(negatives == null ? 0 : negatives);
        if (negatives != null && negatives > 0) {
            log.warn("negative on-hand products={}", negatives);
        }
        return rows.size();
    }
}
```

- [ ] **Step 4: 실행해 통과 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.service.StockReconcilerIT" -q 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL, 3 tests passed.

- [ ] **Step 5: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add src/main/java/com/awesome/backend/inventory/service/StockReconciler.java src/test/java/com/awesome/backend/inventory/service/StockReconcilerIT.java && git commit -m "$(cat <<'EOF'
feat(inventory): 정합성 대조기 — 원장 기준 스냅샷 복구, 불일치·음수 잔고 지표

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: 조정 API + 멱등 키

**Files:**
- Modify: `src/main/java/com/awesome/backend/inventory/entity/InventoryTx.java`
- Modify: `src/main/java/com/awesome/backend/inventory/repository/InventoryTxRepository.java`
- Modify: `src/main/java/com/awesome/backend/inventory/service/StockMovementRecorder.java`, `InventoryService.java`
- Modify: `src/main/java/com/awesome/backend/common/error/ErrorCode.java`
- Modify: `src/main/java/com/awesome/backend/demo/service/DemoProductProvisioner.java`, `src/test/java/com/awesome/backend/support/StockTestSupport.java`, `src/test/java/com/awesome/backend/inventory/service/ConcurrentStockIT.java`, `ShipmentCompleteDeadlockIT.java` (adjust 호출 시그니처)
- Create: `src/main/java/com/awesome/backend/inventory/controller/InventoryAdjustmentController.java`, `InventoryAdjustmentRequest.java`, `InventoryAdjustmentResponse.java`
- Test: `src/test/java/com/awesome/backend/inventory/controller/InventoryAdjustmentControllerIT.java`

**Interfaces:**
- Produces: `StockMovementRecorder.adjust(String gtin, int delta, String idempotencyKey, String reason): AdjustResult` — `record AdjustResult(long txId, int delta, boolean duplicated)`. 기존 `adjust(gtin, delta)`는 삭제하고 호출처는 키를 `"internal-" + UUID`로 넘긴다. `POST /api/v1/admin/inventory/adjustments`.
- 새 `ErrorCode.IDEMPOTENCY_CONFLICT(HttpStatus.CONFLICT)`.

- [ ] **Step 1: 테스트 작성**

```java
package com.awesome.backend.inventory.controller;

import static org.assertj.core.api.Assertions.assertThat;

import com.awesome.backend.inbound.repository.ProductRepository;
import com.awesome.backend.inventory.repository.InventoryTxRepository;
import com.awesome.backend.support.StockTestSupport;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@Import(StockTestSupport.class)
class InventoryAdjustmentControllerIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:18.6");

    private static final String CIDER = "8801234500035";
    private static final String PATH = "/api/v1/admin/inventory/adjustments";

    @LocalServerPort int port;
    @Autowired ObjectMapper objectMapper;
    @Autowired StockTestSupport stock;
    @Autowired ProductRepository productRepository;
    @Autowired InventoryTxRepository inventoryTxRepository;
    private final HttpClient http = HttpClient.newHttpClient();

    @Test
    void 같은_키_재전송은_한_번만_반영되고_duplicated를_돌려준다() throws IOException, InterruptedException {
        stock.set(CIDER, 10);
        String key = "adj-" + System.nanoTime();
        String body = """
                {"gtin":"%s","delta":5,"idempotencyKey":"%s","reason":"실사 보정"}""".formatted(CIDER, key);

        HttpResponse<String> first = post(body);
        HttpResponse<String> second = post(body);

        assertThat(first.statusCode()).isEqualTo(200);
        assertThat(second.statusCode()).isEqualTo(200);
        InventoryAdjustmentResponse r1 = objectMapper.readValue(first.body(), InventoryAdjustmentResponse.class);
        InventoryAdjustmentResponse r2 = objectMapper.readValue(second.body(), InventoryAdjustmentResponse.class);
        assertThat(r1.duplicated()).isFalse();
        assertThat(r2.duplicated()).isTrue();
        assertThat(r2.txId()).isEqualTo(r1.txId());
        assertThat(r2.onHandQty()).isEqualTo(15);
        assertThat(stock.onHand(CIDER)).isEqualTo(15);
    }

    @Test
    void 같은_키에_다른_delta면_409() throws IOException, InterruptedException {
        String key = "adj-" + System.nanoTime();
        post("""
                {"gtin":"%s","delta":1,"idempotencyKey":"%s","reason":"a"}""".formatted(CIDER, key));
        HttpResponse<String> conflict = post("""
                {"gtin":"%s","delta":2,"idempotencyKey":"%s","reason":"b"}""".formatted(CIDER, key));
        assertThat(conflict.statusCode()).isEqualTo(409);
        assertThat(conflict.body()).contains("IDEMPOTENCY_CONFLICT");
    }

    @Test
    void 키가_없으면_400() throws IOException, InterruptedException {
        HttpResponse<String> bad = post("""
                {"gtin":"%s","delta":1,"reason":"x"}""".formatted(CIDER));
        assertThat(bad.statusCode()).isEqualTo(400);
    }

    private HttpResponse<String> post(String body) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create("http://localhost:" + port + PATH))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
        return http.send(request, HttpResponse.BodyHandlers.ofString());
    }
}
```

- [ ] **Step 2: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.controller.InventoryAdjustmentControllerIT" -q 2>&1 | tail -5`
Expected: 컴파일 실패 (`InventoryAdjustmentResponse` 없음).

- [ ] **Step 3: 엔티티·리포지토리·서비스**

`InventoryTx.java`에 필드와 생성자·접근자를 추가한다:
```java
    @Column(name = "idempotency_key")
    private String idempotencyKey;

    @Column(name = "reason")
    private String reason;

    /** 조정 전용 — 멱등 키와 사유를 남긴다. */
    public InventoryTx(Long productId, int qtyDelta, String idempotencyKey, String reason) {
        this(productId, TxType.ADJUST, qtyDelta, null, null);
        this.idempotencyKey = idempotencyKey;
        this.reason = reason;
    }

    public Long id() {
        return id;
    }

    public Long productId() {
        return productId;
    }

    public String idempotencyKey() {
        return idempotencyKey;
    }
```

`InventoryTxRepository.java`:
```java
    Optional<InventoryTx> findByIdempotencyKey(String idempotencyKey);
```
(import `java.util.Optional`)

`ErrorCode.java`에 `IDEMPOTENCY_CONFLICT(HttpStatus.CONFLICT),`를 `OUT_OF_STOCK` 다음 줄에 추가한다.

`StockMovementRecorder.java`:
```java
    /** 관리자 보정 (부호 포함). 같은 키 재전송은 기존 기록을 돌려준다. 같은 키에 다른 delta 는 IDEMPOTENCY_CONFLICT. */
    AdjustResult adjust(String gtin, int delta, String idempotencyKey, String reason);

    record AdjustResult(long txId, int delta, boolean duplicated) {
    }
```
기존 `void adjust(String gtin, int delta);`는 지운다.

`InventoryService.adjust`:
```java
    @Override
    public AdjustResult adjust(String gtin, int delta, String idempotencyKey, String reason) {
        Long productId = product(gtin).id();
        Optional<InventoryTx> existing = inventoryTxRepository.findByIdempotencyKey(idempotencyKey);
        if (existing.isPresent()) {
            InventoryTx tx = existing.get();
            if (tx.qtyDelta() != delta || !tx.productId().equals(productId)) {
                throw new ApiException(ErrorCode.IDEMPOTENCY_CONFLICT,
                        "같은 멱등 키로 다른 조정이 이미 기록돼 있습니다.",
                        Map.of("idempotencyKey", idempotencyKey, "recordedDelta", tx.qtyDelta()));
            }
            return new AdjustResult(tx.id(), tx.qtyDelta(), true);
        }
        InventoryTx saved = inventoryTxRepository.save(new InventoryTx(productId, delta, idempotencyKey, reason));
        return new AdjustResult(saved.id(), delta, false);
    }
```
(import `java.util.Optional`, `ApiException`, `ErrorCode`, `Map` 복원)

호출처 수정 — 전부 `adjust(gtin, delta, "internal-" + java.util.UUID.randomUUID(), "<사유>")` 형태로:
- `DemoProductProvisioner.alignStock`·`pruneDropped`: 사유 `"demo provision"`
- `StockTestSupport.set`: 사유 `"test"`
- `ConcurrentStockIT` 원복 줄, `ShipmentCompleteDeadlockIT` 두 줄: 사유 `"test"`

- [ ] **Step 4: 컨트롤러·요청·응답**

`InventoryAdjustmentRequest.java`:
```java
package com.awesome.backend.inventory.controller;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** 재고 조정 요청. 재전송 대비 멱등 키 필수 (D-L7). */
public record InventoryAdjustmentRequest(
        @NotBlank String gtin,
        int delta,
        @NotBlank @Size(max = 80) String idempotencyKey,
        @Size(max = 200) String reason) {
}
```

`InventoryAdjustmentResponse.java`:
```java
package com.awesome.backend.inventory.controller;

public record InventoryAdjustmentResponse(long txId, String gtin, int delta, int onHandQty, boolean duplicated) {
}
```

`InventoryAdjustmentController.java`:
```java
package com.awesome.backend.inventory.controller;

import com.awesome.backend.inventory.service.AvailableStockQuery;
import com.awesome.backend.inventory.service.StockMovementRecorder;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 재고 조정 (specs/2026-09-23-ledger-stock-design.md D-L7). 조정은 이 경로 하나뿐이다. */
@RestController
@RequestMapping("/api/v1/admin/inventory")
public class InventoryAdjustmentController {

    private final StockMovementRecorder recorder;
    private final AvailableStockQuery stockQuery;

    public InventoryAdjustmentController(StockMovementRecorder recorder, AvailableStockQuery stockQuery) {
        this.recorder = recorder;
        this.stockQuery = stockQuery;
    }

    @PostMapping("/adjustments")
    public InventoryAdjustmentResponse adjust(@Valid @RequestBody InventoryAdjustmentRequest request) {
        StockMovementRecorder.AdjustResult result = recorder.adjust(
                request.gtin(), request.delta(), request.idempotencyKey(), request.reason());
        return new InventoryAdjustmentResponse(result.txId(), request.gtin(), result.delta(),
                stockQuery.onHandQty(request.gtin()), result.duplicated());
    }
}
```

- [ ] **Step 5: 실행해 통과 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.inventory.controller.InventoryAdjustmentControllerIT" -q 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL, 3 tests passed. (400 테스트는 `VALIDATION_ERROR` 핸들러가 `@Valid` 실패를 400 으로 매핑하는 기존 동작에 의존한다.)

- [ ] **Step 6: 전체 테스트**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test -q 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 7: 커밋**

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add -A src/main src/test && git commit -m "$(cat <<'EOF'
feat(inventory): 재고 조정 API — 멱등 키 필수, 재전송은 기존 기록 반환

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: 시연 리셋과 스냅샷

**Files:**
- Modify: `src/main/java/com/awesome/backend/demo/service/DemoStateResetter.java`
- Test: `src/test/java/com/awesome/backend/demo/controller/DemoResetIT.java` (기존 테스트가 통과하는지 확인, 필요 시 단언 추가)

**Interfaces:**
- Consumes: 없음. 리셋이 원장을 지우므로 스냅샷도 0 으로 돌려야 실재고가 0 이 된다.

- [ ] **Step 1: 테스트 추가** — `DemoResetIT`에 추가:

```java
    @Test
    void 리셋_뒤_실재고는_시연_명세_수량과_같고_스냅샷은_원장과_일치한다() throws Exception {
        mvc.perform(post("/api/v1/admin/demo/reset")).andExpect(status().isOk());
        Long mismatches = jdbcTemplate.queryForObject("""
                select count(*) from stock_balance b
                 where b.qty + coalesce((select sum(t.qty_delta) from inventory_tx t
                                          where t.product_id = b.product_id and t.id > b.last_tx_id), 0)
                    <> coalesce((select sum(t.qty_delta) from inventory_tx t where t.product_id = b.product_id), 0)
                """, Long.class);
        assertThat(mismatches).isZero();
    }
```
(`DemoResetIT`가 `JdbcTemplate`·`MockMvc`를 이미 쓰는지 확인하고 없으면 `@Autowired JdbcTemplate jdbcTemplate;`를 추가. `mvc`는 그 클래스의 기존 방식(MockMvc 또는 HttpClient)을 따른다.)

- [ ] **Step 2: 실행해 실패 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.demo.controller.DemoResetIT" -q 2>&1 | tail -8`
Expected: 새 테스트 FAIL (원장을 지운 뒤 스냅샷이 옛 값을 유지해 불일치).

- [ ] **Step 3: `DemoStateResetter.clearDemoData`에 한 줄 추가**

`jdbcTemplate.update("delete from inventory_tx");` 다음 줄에:
```java
        jdbcTemplate.update("update stock_balance set qty = 0, last_tx_id = 0, computed_at = now()");
```
주석: `// 원장을 비웠으므로 스냅샷도 0 — 실재고 = 스냅샷 + 미집계 원장 이 0 이 된다 (specs/2026-09-23-ledger-stock-design.md 8절).`

- [ ] **Step 4: 실행해 통과 확인**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test --tests "com.awesome.backend.demo.controller.DemoResetIT" -q 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: 전체 테스트 + 커밋**

Run: `cd /Users/idong-u/d/cjj-portfolio/backend && ./gradlew test -q 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL. 총 테스트 수 = 241 + 신규(데드락 1, 스냅샷 4, 읽기 1, 쓰기 2−1, 집계 3, 대조 3, 조정 3, 리셋 1).

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git add -A src/main/java/com/awesome/backend/demo src/test/java/com/awesome/backend/demo && git commit -m "$(cat <<'EOF'
fix(demo): 리셋 시 잔고 스냅샷도 0 으로 — 원장과 일치 유지

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: 배포·재측정·기록

**Files:**
- Modify: `/Users/idong-u/d/cjj-portfolio/docs/evidence/loadtest/README.md` (실행 5 절 추가)
- Modify: `/Users/idong-u/d/cjj-portfolio/tools/loadtest/monitoring/grafana/dashboards/cjj-loadtest.json` (지표 패널 1개 추가)

**Interfaces:**
- Consumes: 부하 발생기 `43.203.152.223`의 `~/loadtest/run.sh packing`, 토트 목록 `~/loadtest/k6/totes.json`(미사용 구간 6,000 이후), Prometheus `http://13.124.19.3:9090`, `tools/loadtest/analyze.py --profile packing`.

- [ ] **Step 1: 백엔드 배포** — `backend` 저장소를 원격 `main`에 push 하면 `build-push.yml`·`deploy-ec2.yml`이 배포한다. 배포 완료(헬스 체크 통과)를 Actions 에서 확인하고 Grafana 의 deploy 주석 시각을 적어 둔다.

```bash
cd /Users/idong-u/d/cjj-portfolio/backend && git push origin HEAD:main
```

- [ ] **Step 2: 마이그레이션 적용 확인**

```bash
ssh -i ~/cjj/key.pem ubuntu@13.124.19.3 'cd ~/backend; set -a; source .env; set +a; docker run --rm -i --network host -e PGPASSWORD="$POSTGRES_PASSWORD" postgres:18 psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -c "select count(*) from stock_balance;" -c "select version, success from flyway_schema_history order by installed_rank desc limit 1;"'
```
Expected: `stock_balance` 행 수 = 상품 수, 최신 버전 21 success `t`.

- [ ] **Step 3: 50명 포장 재실행 (실행 4와 같은 조건, 미사용 토트)**

```bash
ssh -i ~/cjj/key.pem ubuntu@43.203.152.223 'cd ~/loadtest && source <(grep ^export /tmp/run3.sh) && bash run.sh packing -e VUS=50 -e DURATION=3m -e OFFSET=6000 -e TOTES_FILE=/home/ubuntu/loadtest/k6/totes.json 2>&1 | grep -E "^run=|complete_duration|http_req_failed|iterations|✗|✓ [0-9]"'
```
Expected: `complete 2xx` 실패 0, `http_req_failed` 0.00%, `complete_duration` p95 가 실행 4(10.07초)보다 크게 낮음(박스 행 락 대기만 남으므로 수백 ms 수준 예상).

- [ ] **Step 4: 결과 동기화·표·캡처**

```bash
cd /Users/idong-u/d/cjj-portfolio && R=$(ssh -i ~/cjj/key.pem ubuntu@43.203.152.223 'ls -t ~/loadtest/results | grep packing | head -1') && rsync -az -e "ssh -i $HOME/cjj/key.pem" ubuntu@43.203.152.223:~/loadtest/results/$R docs/evidence/loadtest/ && python3 tools/loadtest/analyze.py --prom http://13.124.19.3:9090 --profile packing --start "<시작 KST>" --end "<종료 KST>" --step 30s > docs/evidence/loadtest/$R/packing-window-table.md
```
Grafana 캡처는 실행 4와 같은 방법(playwright, kiosk URL, 1600×2400)으로 `docs/evidence/loadtest/$R/grafana-packing-after.png`에 둔다. 서버 측 상태 분포·데드락 수는 실행 4에서 쓴 Prometheus 쿼리(`http_server_requests_seconds_count` by status, `pg_stat_database_deadlocks` increase)로 뽑는다.

- [ ] **Step 5: 정합성 훼손 실험**

```bash
ssh -i ~/cjj/key.pem ubuntu@13.124.19.3 'cd ~/backend; set -a; source .env; set +a; docker run --rm -i --network host -e PGPASSWORD="$POSTGRES_PASSWORD" postgres:18 psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -c "update stock_balance set qty = qty + 500 where product_id = (select id from product where gtin = '"'"'8801007038780'"'"');"; date -u'
```
그 뒤 Prometheus 에서 `inventory_reconcile_mismatch` 가 1 이 되는 시각과 다시 0 이 되는 시각을 기록한다(60초 이내여야 한다). `v_stock_on_hand` 값이 원장 합과 같아졌는지 psql 로 확인한다.

- [ ] **Step 6: 1,000주문 배치 1건 재측정(부작용 확인)**

```bash
ssh -i ~/cjj/key.pem ubuntu@43.203.152.223 'cd ~/loadtest && source <(grep ^export /tmp/run3.sh) && bash run.sh orders_import -e ORDERS=1000 -e RATE=1 -e DURATION=10s -e TIMEOUT=300s -e GRACEFUL=300s 2>&1 | grep -E "^run=|import_duration|http_req_failed"'
```
Expected: 응답 시간이 실행 3(52.5초)과 같은 수준. 크게 달라지면 가용 계산 쿼리 비용을 의심한다.

- [ ] **Step 7: 대시보드에 재고 지표 패널 추가**

`cjj-loadtest.json`의 "원인 2 · 포화도" 행에 timeseries 패널 하나를 추가한다: 제목 `재고 원장 — 집계 지연 · 불일치 · 음수 잔고`, 쿼리 3개 `inventory_collector_lag_rows`, `inventory_reconcile_mismatch`, `inventory_balance_negative`. 기존 패널 JSON 하나를 복사해 `id`·`gridPos`·`title`·`targets[].expr`만 바꾼다.

- [ ] **Step 8: README 실행 5 절 작성**

`docs/evidence/loadtest/README.md` 끝에 `## 실행 5 — 원장 기반 재고 적용 후 동시 포장 50명 (날짜 KST)` 절을 추가한다. 내용: 시나리오는 실행 4와 동일, 표는 실행 4(50명) 열 옆에 실행 5 열을 나란히(완료 시도·성공/실패·처리량·p50/p95/max·스캔 p95·데드락·Hikari pending·Tomcat busy·CPU), 데드락 재현 테스트 전후(`deadlock-repro-before.txt`·`after.txt`), 정합성 훼손 실험의 감지·복구 시각, 1,000주문 배치 비교. 판독은 "원인 → 제거한 것 → 남은 것(박스 행 락, 접수 경합)" 순서로 쓴다. 문체는 이 README 의 앞 절과 같다.

- [ ] **Step 9: 커밋(cjj-portfolio) + 서브모듈 포인터**

```bash
cd /Users/idong-u/d/cjj-portfolio && git add backend docs/evidence/loadtest tools/loadtest/monitoring/grafana/dashboards/cjj-loadtest.json && git commit -m "$(cat <<'EOF'
evidence(loadtest): 실행 5 — 원장 기반 재고 적용 후 동시 포장 50명 전후 비교

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## 자가 검토

- 스펙 대응: D-L1(Task 5·6), D-L2(Task 2·3), D-L3(Task 5), D-L4(Task 2), D-L5(Task 7·8), D-L6(Task 8), D-L7(Task 9), 집계 지연 지표(Task 7), 뷰(Task 2), 시연 경로(Task 5·10), 테스트 1~7(Task 1·2·3·5·7·8·9), 측정 4항목(Task 11).
- 타입 일관성: `StockMovementRecorder.AdjustResult(long txId, int delta, boolean duplicated)`를 Task 9 컨트롤러가 그대로 쓴다. `StockBalanceRepository.onHandQty(Long)`을 Task 3·8·9 가 쓴다. `StockTestSupport.set/onHand`를 Task 4·6·9 가 쓴다.
- 순서 의존: Task 4(테스트 헬퍼)가 Task 5(컬럼 제거)보다 앞이라 스위트가 중간에 깨지지 않는다. Task 9 의 `adjust` 시그니처 변경은 Task 4·5 에서 만든 호출처를 같은 태스크에서 고친다.
