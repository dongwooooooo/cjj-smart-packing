# 진행 기록 — 촬영 사진 업로드 A/C 실측

계획·예측: `PLAN.md`. 시각은 KST.

- 09-26 18:24 EC2 SSH·Prometheus·Grafana 접속 실패(ssh: connect to host … port 22: Operation timed out). 공인 IP 117.111.6.13 보고, 보안 그룹 반영 뒤 18:26 `pool-sweep.sh check` 성공.
- 09-26 18:28 기준 상태: 백엔드 이미지 `cj-ai-backend:latest`(cd6222eefbf2), SPRING_APPLICATION_JSON 없음, 업로드 풀 지표 `executor_*{name="imageUploadExecutor"}` 이미 노출(최대 스레드 6). RDS CPU 크레딧 22.7(18:16).
- 09-26 18:29 C 이미지 빌드: git archive a73311e → `cj-ai-backend:upload-c` (4d64567427fc, 43초). 소스 EC2 ~/upload-c-src
- 09-26 18:3x 예측 기록(PLAN.md "측정 전 예측"): M1 C p95 +30ms 이내 / M2 A 10·30명 60초 뒤 PENDING 0(실행 2 기준 적체는 45명부터) / M3 A PENDING>0·C 0 / M4 C p95 상승·유실 0.
- 09-26 18:32 `m1-A` client e2e (ms): {'n': 55, 'failed': 0, 'p50': 436.9, 'p95': 466.6, 'p99': 668.5, 'max': 668.5, 'mean': 443.5, 'failReasons': {}}
- 09-26 18:33 `m1-C` client e2e (ms): {'n': 55, 'failed': 0, 'p50': 444.2, 'p95': 482.4, 'p99': 494.2, 'max': 494.2, 'mean': 446.9, 'failReasons': {}}
- 09-26 18:35 `m1-C-r2` client e2e (ms): {'n': 55, 'failed': 0, 'p50': 440.1, 'p95': 473.7, 'p99': 551.0, 'max': 551.0, 'mean': 443.5, 'failReasons': {}}
- 09-26 18:36 `m1-A-r2` client e2e (ms): {'n': 55, 'failed': 0, 'p50': 437.4, 'p95': 490.5, 'p99': 528.0, 'max': 528.0, 'mean': 439.3, 'failReasons': {}}
- 09-26 18:41 `m2-A-v10` 요청 1259 (INFERRED 아님 0 ) p50/p95/p99/max 423/535/557/585ms, 사진 종료 직후 {'STORED': 3777} → 정착 뒤 {'STORED': 3777}, 업로드 풀 활성 최대 3 큐 최대 1 CallerRuns , 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 23.5→23.2
- 09-26 18:41 `m2-A-v10` 정착 대기가 60초가 아니라 10초로 돌았다(pool-sweep.env 의 SETTLE_S=10 이 기본값을 덮음). 종료 뒤 12초 시점에 이미 PENDING 0 이라 결론은 같다. 변수 이름을 AB_SETTLE_S 로 바꾸고, 종료 직후 집계를 12초 대기 앞으로 옮겼다.
- 09-26 18:47 `m2-A-v30` 요청 3809 (INFERRED 아님 0 ) p50/p95/p99/max 416/524/545/651ms, 사진 종료 직후 {'STORED': 11427} → 정착 뒤 {'STORED': 11427}, 업로드 풀 활성 최대 3 큐 최대 33 CallerRuns , 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 23.5→23.5
- 09-26 18:53 `m2-C-v10` 요청 1260 (INFERRED 아님 0 ) p50/p95/p99/max 420/536/550/617ms, 사진 종료 직후 {'STORED': 3780} → 정착 뒤 {'STORED': 3780}, 업로드 풀 활성 최대 3 큐 최대 4 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 23.5→23.9
- 09-26 18:58 `m2-C-v30` 요청 3738 (INFERRED 아님 0 ) p50/p95/p99/max 419/544/607/1051ms, 사진 종료 직후 {'STORED': 11214} → 정착 뒤 {'STORED': 11214}, 업로드 풀 활성 최대 3 큐 최대 27 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 23.9→24.1
- 09-26 19:04 `m3-A` 요청 1262 (INFERRED 아님 130 {'http_0': 130}) p50/p95/p99/max 431/571/676/1955ms, 사진 종료 직후 {'STORED': 3396} → 정착 뒤 {'STORED': 3396}, 업로드 풀 활성 최대 3 큐 최대 4 CallerRuns , 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 24.1→24.4
- 09-26 19:10 `m3-C` 요청 1270 (INFERRED 아님 120 {'http_0': 120}) p50/p95/p99/max 428/552/617/2060ms, 사진 종료 직후 {'STORED': 3450} → 정착 뒤 {'STORED': 3450}, 업로드 풀 활성 최대 3 큐 최대 13 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 24.4→24.8
- 09-26 19:04 `m3-A` 예측 불일치: 재시작(SIGTERM) 뒤 PENDING 0. Tomcat 정상 종료가 2ms 에 끝났고(`Commencing graceful shutdown` → `Graceful shutdown complete`), 업로드 큐는 최대 4 라 종료 전에 비었다. 실패 응답 130건은 전부 재기동 13초 동안의 연결 실패(http_0).
- 09-26 19:10 `m3-C` PENDING 0, 실패 응답 120건(http_0). 정상 종료가 진행 중 요청을 356ms 안에 마쳤다.
- 09-26 19:11 보조 조건 M3k 추가(설계안 2절 "크래시면 즉시 소실"): 부하 중 60초 시점 `docker compose kill -s SIGKILL backend` 뒤 `start`. 작업자 30명(약 19 req/s)으로 올려 커밋 뒤 업로드 중인 세션이 kill 시점에 있을 확률을 높인다. 예측: A 는 커밋됐으나 업로드 전인 세션이 PENDING 으로 남는다(약 19 req/s × 업로드 0.11초 ≈ 2세션 = 약 6장, 큐 적체분 추가). C 는 PENDING 0, 끊긴 요청은 세션이 커밋되지 않아 DB 에 남지 않는다(S3 에 고아 객체는 남을 수 있음).
- 09-26 19:16 `m3k-A-v30` 요청 3803 (INFERRED 아님 390 {'http_0': 390}) p50/p95/p99/max 425/564/738/2620ms, 사진 종료 직후 {'STORED': 10239} → 정착 뒤 {'STORED': 10239}, 업로드 풀 활성 최대 3 큐 최대 30 CallerRuns , 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 24.8→25.3
- 09-26 19:23 `m3k-C-v30` 요청 3801 (INFERRED 아님 413 {'http_0': 413}) p50/p95/p99/max 422/562/1014/2606ms, 사진 종료 직후 {'STORED': 10164} → 정착 뒤 {'STORED': 10164}, 업로드 풀 활성 최대 3 큐 최대 65 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 25.3→25.5
- 09-26 19:23 M3k 결과: A·C 모두 PENDING 0(아래 표). A 는 kill 직전 0.7초 동안 새 촬영 완료 없이 업로드 대기분(세션 32082~32096)이 마저 올라간 뒤 종료됐다 — 1회 시행이라 kill 시점에 따라 달라질 수 있다. M4 는 정착 대기를 120초로 늘려 A 의 대기 줄이 빠지는 시간을 본다.
- 09-26 19:30 `m4-A` 요청 7529 (INFERRED 아님 0 ) p50/p95/p99/max 417/540/575/806ms, 사진 종료 직후 {'PENDING': 2116, 'STORED': 20471} → 정착 뒤 {'PENDING': 18, 'STORED': 22569}, 업로드 풀 활성 최대 6 큐 최대 1974 CallerRuns , 로그 {'rejected': 12, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 25.5→25.5
- 09-26 19:36 `m4-C` 요청 6032 (INFERRED 아님 0 ) p50/p95/p99/max 788/946/1052/1976ms, 사진 종료 직후 {'STORED': 18096} → 정착 뒤 {'STORED': 18096}, 업로드 풀 활성 최대 3 큐 최대 75 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 25.5→25.4
- 09-26 19:37 M4 결과: A 는 큐 최대 1,974·활성 6·거절 6건(로그 12줄 = 예외+원인), 종료 직후 PENDING 2,116장, 120초 뒤 18장(6세션) 잔존. C 는 유실 0 이지만 응답 p50/p95 788/946ms(A 417/540). C 서버 구간: 업로드 p50 688ms, 업로드 대기 p50 340·p95 512ms. 큐 최대 75(용량 200 미만)라 풀이 코어 3에서 늘지 않았고 CallerRuns 도 0 — 병목은 업로드 스레드 3개. 보조 조건 C6(코어 3 → 6, backend exp/upload-c-core6 b837925, 병합 대상 아님)을 M4 로 한 번 더 잰다. 예측: 풀 처리량이 약 2배라 p95 가 A 근처(600ms 이하)로 돌아온다.
- 09-26 19:38 C 이미지 빌드: git archive b837925 → `cj-ai-backend:upload-c6` (7b660aa0ff1d, 43초). 소스 EC2 ~/upload-c-src
- 09-26 19:45 `m4-C6` 요청 7540 (INFERRED 아님 0 ) p50/p95/p99/max 414/540/571/1059ms, 사진 종료 직후 {'STORED': 22620} → 정착 뒤 {'STORED': 22620}, 업로드 풀 활성 최대 6 큐 최대 53 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0}, RDS 크레딧 25.4→25.6
- 09-26 19:45 복원: 이미지 cd6222eefbf2(기준 cd6222eefbf2), 데모 리셋, measurement_image 0행
- 09-26 19:44 `m4-C6` 응답 p50/p95 414/540ms(A 417/540), upload.wait p95 0ms, 활성 6·큐 최대 53, 유실 0. 예측(600ms 이하) 일치.
- 09-26 19:45 복원 확인: 백엔드 이미지 cd6222eefbf2(기준과 일치), SPRING_APPLICATION_JSON 흔적 0, 데모 리셋, measurement_image 0행. EC2 에 `cj-ai-backend:upload-c`·`upload-c6` 이미지와 `~/upload-c-src`, 부하 발생기에 `~/upload-ab` 를 남겼다. S3 `measurements/` 객체 186,936개(C 형식 80,964)는 삭제하지 않았다.
- 09-26 19:5x 부하 조건 backend.log 를 구간 로그·경고만 남겨 gzip(전체 29MB → 증거 디렉터리 5MB). 표·그림은 `tools/loadtest/upload-ab-report.py` 로 생성(`tables.md`, `m2-response-p95.png`, `m3-pending.png`, `m4-pending.png`).
