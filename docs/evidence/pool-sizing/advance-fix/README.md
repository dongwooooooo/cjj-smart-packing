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

## RDS 실측 (2026-09-26 12:40 ~ 13:34, `rds/`)

환경: RDS db.t4g.micro(PostgreSQL 18.3, `jit` 기본값 off), 백엔드 EC2 c7i-flex.large. 이전 이미지 = 실험 전 배포 이미지(main f87a37e, id cd6222eefbf2). 이후 이미지 = 01d8107 소스를 EC2 에서 빌드한 `cj-ai-backend:advance-fix`(id c19a0be8c8f5, `git archive` → `docker build`, 80초). 원장은 `tools/loadtest/sweep/synth-ledger.sql` 로 합성 행 1,031,137개(ref_type `SYNTH`, 상품 10~17, 전부 정착 창 밖)를 넣어 20,317 → 1,051,454행으로 만들고, 스냅샷은 상품 10~17 을 마지막 행까지 접은 상태, 1~9 는 (0,0). 합성 행의 qty ±1 이 상품 짝홀과 겹쳐 상품 10·12·14·16 잔고가 +12.9만, 11·13·15·17 이 −12.9만이 됐다. 포장 완료는 상품 잔고를 검사하지 않아 처리량에는 영향이 없다.

예측(`../progress.md` 에 실행 전 기록): 무부하 RDS CPU 이전 16~18%, 이후 기준선 5~6% 근처. 포화 처리량 이후 122~125건/s 근처, 이전 60~70건/s 대.

### EXPLAIN (ANALYZE, BUFFERS) — 원장 1,051,454행

| SQL | jit off(RDS 기본) | jit on |
| --- | ---: | ---: |
| 이전(`advance-before.sql`) | 3,393ms, 버퍼 498,555 | 6,348ms |
| 이후(`advance-after.sql`) | **0.66ms**, 버퍼 105 | 9,215ms(대부분 JIT 컴파일) |

원본: `rds/rds-ledger-1051454-{before,after}-jit{on,off}.txt`. RDS 이전/로컬 이전 비율은 3,393/1,371 = 2.5 배(jit off 끼리)로, 2만 행 비율(2.0)을 외삽한 추정 2.85초보다 길었다.

### 무부하 RDS CPU (CloudWatch 1분 평균, `rds/idle-cpu-1min.json`, 시각 `rds/idle-windows.txt`)

| 구간 | 백엔드 | 1분 평균 |
| --- | --- | --- |
| 12:40~12:50 | 이전 이미지, 원장 합성 전(20,317행) | 5.0~6.0% |
| 12:53~12:57 | 이전 이미지, 원장 1,051,454행 | 25.6~29.7% |
| 12:59~13:02 | 이후 이미지, 원장 1,051,454행 | 5.4~6.6% |

12:51~12:52 는 EXPLAIN 실행, 12:58 은 이미지 교체 시점이라 뺐다. 이전 이미지는 예측(16~18%)보다 높은 25.6~29.7% 였다. EXPLAIN 3.39초로 계산하면 3.39/8.39 = 코어 1개의 40%, 2 vCPU 의 약 20% 이고, 나머지 약 1~4%p 는 미확인(LAG·대조기 후보).

### 포화 부하 A/B (작업자 100명 연속, 풀 10, connectionTimeout 3초, 판독 180초, `rds/ab/`)

원장은 되돌리지 않았다(조건마다 배송단위 묶음만 원복). 순서 이전 → 이후 → 이후 → 이전.

| 순서 | 시작 | 이미지 | 원장 행(시작 → 끝) | 완료/s | 서버 완료 p95 | 실패율 | 획득 타임아웃 | RDS CPU | 크레딧(시작 전) |
| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 13:07 | 이전 | 1,051,454 → 1,092,792 | 84.9 | 1,107ms | 0.24% | 115 | 67.4% | 24.3 |
| 2 | 13:14 | 이후 | 1,092,792 → 1,150,364 | 117.3 | 512ms | 0.03% | 16 | 56.7% | 23.2 |
| 3 | 13:20 | 이후 | 1,150,364 → 1,208,757 | 118.0 | 499ms | 0.005% | 3 | 54.5% | 13.3 |
| 4 | 13:27 | 이전 | 1,208,757 → 1,229,727 | 42.9 | 2,654ms | 5.55% | 1,453 | 61.6% | 9.7 |

- 이후 이미지는 원장이 109만 → 121만 행으로 느는 동안 처리량이 117.3 → 118.0건/s 로 그대로였다. 원장 원복 스윕의 같은 조건(풀 10, 원장 2만 행) 122.3~125.4건/s 보다 4~6% 낮다.
- 이전 이미지는 원장 105만~109만 행에서 84.9, 121만~123만 행에서 42.9건/s 로, 원장이 11% 늘자 처리량이 절반이 됐다. 예측(60~70건/s 대)은 두 값 사이였다.
- 3초 획득 타임아웃은 이후 이미지에서도 16건·3건 났다(획득 max 3.01초). 원장 원복 재검증(`verify-controlled/`)에서 획득 max 2.02~2.996초로 한도에 붙어 있던 것과 같은 풀 대기열의 꼬리다.
- RDS CPU 크레딧은 13:30 에 0 이 됐다(5분 지표, 4번 조건 끝 무렵). 청구된 초과 크레딧 0.

### 정리 (13:34)

합성 행 삭제(`synth-ledger-delete.sql`) → 실험 원장 원복(`ledger-reset.sql`) → 묶음 원복. 원장 20,317행(SYNTH 0), 상품 10~17 잔고 94,017~94,364(실험 전 값). 백엔드 컨테이너는 이전 이미지(cd6222eefbf2), `SPRING_APPLICATION_JSON`·`JAVA_TOOL_OPTIONS`·덮어쓰기 파일 없음, hikari max 10, tomcat max 200. `cj-ai-backend:advance-fix` 이미지와 `~/advance-fix-src` 는 EC2 에 남겨 두었다(배포에는 쓰이지 않음).

