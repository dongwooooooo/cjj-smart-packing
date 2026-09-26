# 집계기 ADVANCE 재작성 — 로컬 실행 계획 전후 (2026-09-26)

환경: Docker `postgres:18.6`, Apple M2 Pro. 합성 원장은 `../drift-query/local-setup.sql`·`local-load.sql`(상품 1~9 커서 0·원장 없음, 10~17 정착 창 밖까지 집계된 상태). 수정 코드: backend 브랜치 `fix/collector-advance-cost` 커밋 01d8107.

| 원장 행 | 이전(jit on / off) | 이후(jit on / off) |
| ---: | ---: | ---: |
| 20,317 | 25.0ms / 27.7ms | 6.0ms / 6.3ms |
| 1,051,454 | 1,412ms / 1,371ms | 288ms / 6.6ms |

- 이전 SQL은 `MAX(t.id)`·`MIN(y.id)` 서브쿼리가 MIN/MAX 인덱스 최적화로 `inventory_tx_pkey`를 id 순으로 걸으며 `product_id`·`created_at`으로 행을 버린다. 커서 0인 상품 9개는 매번 원장 전체를 훑는다(loop당 약 55.7만 행 폐기).
- 이후 SQL은 `MAX(...) FILTER (...)`·`MIN(...) FILTER (...)`라 그 최적화 대상이 아니다. 플래너가 `ix_inventory_tx_product_id (product_id, id)`로 커서 이후 행만 읽는다(상품당 평균 337~716행).
- 이후 SQL의 jit on 288ms는 전부 JIT 컴파일(Inlining 67 + Optimization 84 + Emission 92ms)이다. 추정 행수(43,811)가 실제(337)보다 커서 비용이 JIT 임계를 넘는다. 애플리케이션은 `spring.datasource.hikari.connection-init-sql: SET jit = off`로 끈다.
- 원본 계획: `local-<행수>-<before|after>-jit<on|off>.txt`. SQL: `advance-before.sql`, `advance-after.sql`. 요약: `summary.txt`.
- RDS 실측은 미완 — 배포 후 원장 105만 행 상태에서 무부하 CPU·포장 완료 처리량을 이전·이후 이미지로 비교한다.
