# 브리프 — 촬영 응답 경로에서 사진 저장을 트랜잭션·응답 뒤로 빼기 (문제 2 레버)

작업 위치: `/Users/idong-u/cjj/backend` (git worktree, 현재 브랜치 `measure/inference-path`). 여기서 새 브랜치 `feat/async-image-store`를 만들어 작업한다.
`/Users/idong-u/cjj/backend-weight`(다른 워크트리)는 절대 건드리지 않는다. 푸시하지 않는다. V1~V12 마이그레이션 수정 금지. 문서·주석 한국어, 코드 영어.

## 배경

촬영 1회(`POST /api/v1/inbound/measurements`)는 사진 3장을 읽고, Lambda 추론을 부르고, **세션을 커밋하면서 사진 3장을 ImageStore에 동기로 쓴 뒤**, 응답한다.
로컬 실측(RIE 구성, 2026-09-14)에서 백엔드 구간 중 저장(saveMs)이 가장 컸다: p50 32~81ms, p95 144~227ms — 로컬 파일 저장인데도 그렇다. 운영은 `S3ImageStore`가 사진 3장을 S3에 동기로 put 하고, 그 호출이 트랜잭션 안에 있다(메모리: "현재 S3 put in TX 결함"). 계약을 8초에서 1초 p95로 조이면 이 구간이 예산의 큰 몫을 먹는다.

## 결정 (확정)

1. 사진 업로드를 **트랜잭션 밖 + 응답 뒤**로 뺀다. 세션은 사진 키를 미리 정해 커밋하고, 커밋 후 이벤트(`@TransactionalEventListener(phase = AFTER_COMMIT)`)로 비동기 업로드(`@Async`, 전용 executor, 스레드 이름 `image-upload-`). 응답은 업로드를 기다리지 않는다.
2. 업로드 실패는 삼키지 않는다: 최대 3회 재시도(간격 설정값, 기본 1초) 후에도 실패하면 WARN 로그 + `measurement_image`(또는 대응 엔티티)에 업로드 실패 표시가 남아야 한다. 스키마 변경이 필요하면 새 Flyway 마이그레이션(V13 이후 번호는 `backend-weight`의 V13과 충돌하니 **V20**부터 쓴다)으로 컬럼 하나만 추가한다.
3. 이미지 조회(1-6, `/products/{id}/images`)는 업로드 전이면 해당 사진을 목록에서 빼거나 `pending` 표시를 한다 — 없는 객체의 presigned URL을 돌려주지 않는다. 계약 변경은 최소로, 응답 형태를 바꾸면 `docs/`가 아니라 코드 주석과 이 작업의 결정 문서(`docs/decisions-async-image-store.md`)에만 적는다.
4. 로컬 파일 저장(`LocalImageStore`)도 같은 비동기 경로를 탄다(코드 경로 하나).
5. 측정은 **S3 경로**로 한다. 로컬에 MinIO를 띄워 `S3ImageStore`를 그대로 쓴다(엔드포인트 오버라이드 + path-style). 실 S3가 아니므로 결과 표에 "MinIO(localhost) 기준, 실 S3는 리전 RTT가 추가됨"을 명시한다.

## 측정 스택 (이미 떠 있음 — 반드시 이 이름·포트로만)

- compose 프로젝트명 `cjj-measure`, 백엔드 `:8010`, DB `:5433`, 오버레이 파일 `/private/tmp/claude-501/-Users-idong-u-cjj/0c3bfd62-e675-4c27-b46c-cdcc7811107e/scratchpad/docker-compose.measure.yml`
- 추론은 RIE 컨테이너 `dimension-rie`(`:9000`)로 간다. 건드리지 않는다.
- **경고**: 이 맥에는 다른 세션의 compose 프로젝트 `backend`(포트 8000, WMS)가 떠 있다. `-p cjj-measure` 없이 `docker compose`를 절대 실행하지 않는다. `pkill -f`는 자기 셸까지 죽일 수 있으니 `pkill -x`만 쓴다.
- 기동 명령(오버레이는 로컬 jar를 싣는 인라인 Dockerfile을 쓴다 — 먼저 `./gradlew bootJar --no-daemon`):
  ```
  cd /Users/idong-u/cjj/backend && ./gradlew bootJar --no-daemon -q
  MEASURE_IMAGES_DIR=/private/tmp/claude-501/-Users-idong-u-cjj/0c3bfd62-e675-4c27-b46c-cdcc7811107e/scratchpad/images-large/images \
    docker compose -p cjj-measure -f docker-compose.yml -f docker-compose.override.yml -f <오버레이> up -d --build
  ```
- MinIO는 오버레이에 서비스로 추가한다(이미지 `minio/minio`, 포트 9100:9000 — 9000은 RIE가 쓴다, 콘솔 불필요). 백엔드 env: `STORAGE_BUCKET=measure-images`, `STORAGE_ENDPOINT_OVERRIDE=http://minio:9000`, 더미 자격증명. 버킷은 기동 시 `mc` 또는 백엔드 시작 훅으로 만든다 — 간단한 쪽. `S3ImageStore`/`StorageConfig`에 엔드포인트 오버라이드·path-style·정적 자격증명 설정을 추가한다(`INFERENCE_ENDPOINT_OVERRIDE`와 같은 패턴, 비우면 실 AWS).
- 측정 스크립트: `/private/tmp/claude-501/-Users-idong-u-cjj/0c3bfd62-e675-4c27-b46c-cdcc7811107e/scratchpad/measure_e2e.py <profile> 5 1` (large / small). 백엔드 로그의 `measure.timing`·`inference.timing` 줄을 파싱한다. saveMs가 "세션 커밋 + 동기 업로드"였으므로, 변경 후에는 saveMs에 업로드가 빠지고 별도 로그 `upload.timing sessionId=.. uploadMs=..`를 남겨 업로드가 실제로 끝나는 시간도 기록한다.

## 구현 단위 (순서대로, 단위마다 `./gradlew test --no-daemon -q` green + 커밋)

U1. MinIO + S3 엔드포인트 오버라이드: 오버레이 수정, `StorageConfig` 설정 추가. 스택 재기동해 S3ImageStore 경로로 촬영이 성공하는지 확인(`INFERRED` + 사진 3장이 MinIO 버킷에 있음).
U2. **변경 전 기준 측정**: large·small 각 5회×11상품, 결과 JSON을 `measure-before-{profile}.json`으로 스크래치패드에 보존. 표로 정리.
U3. 비동기 업로드 구현(결정 1~4). 기존 테스트 green 유지. 새 테스트: (a) 저장 직후 세션은 커밋돼 있고 업로드는 아직일 수 있음, (b) 커밋 후 업로드가 실제로 일어남, (c) 업로드 실패 시 재시도 후 실패 표시, (d) 업로드 전 이미지 조회가 없는 객체 URL을 돌려주지 않음.
U4. **변경 후 측정**: 같은 조건, `measure-after-{profile}.json`. 전후 표(client e2e / saveMs / totalMs / uploadMs 별도).
U5. 문서: `docs/decisions-async-image-store.md` — 배경, 대안(동기 유지 / 트랜잭션 밖 동기 / AFTER_COMMIT 비동기 / 큐 기반), 채택 이유, 실패 처리, 전후 수치, 한계(MinIO 기준, 로컬 노이즈).

## 하지 말 것

- 추론 호출 경로·`LambdaInferenceClient`·`MeasurementService`의 타이밍 로그 형식 변경 금지(측정 스크립트가 파싱한다).
- 메시지 큐·외부 워커 도입 금지(대안 표에만).
- 오버레이 외의 compose 파일, `.env`, `demo/` 수정 금지.

## 완료 보고

단위별 파일·테스트 수·커밋 해시, 전후 측정 표(profile × 지표), 남은 결정. 저장소 안에 보고서 쓰지 않는다.
