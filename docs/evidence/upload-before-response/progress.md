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

## 후속 1 — 업로드 9.9초의 원인과 수정 (09-26 20:0x~)

- 20:0x 원인 분리(기존 증거): `m2-A-v30` 에서 `upload.timing uploadMs` > 2초는 11,427장(3,809작업) 중 1건(sessionId=18761, 09:43:32.462Z 종료, 9,918ms)뿐. 나머지 10개 조건(A·C, M2~M4)에서 load·upload·save 어느 구간도 2초를 넘은 적이 없다. 같은 시각 다른 두 업로드 스레드는 94~143ms 로 정상이고, 사진 읽기(S3 GET, 요청 스레드) p99 97ms, GC 일시정지 최대 27ms, 요청률 21 req/s 일정 → 전역 지연이 아니라 그 1건만 멈췄다. 우리 코드 재시도 로그(`사진 업로드 재시도`)·SDK 예외·WARN 은 0줄 → 호출은 결국 성공했고, 늦어진 시간은 SDK 안(재시도·커넥션 획득 대기·멈춘 연결)에서 쓰였다. 기존 로그는 세 장 합계만 있어 어느 put 이 몇 번 시도했는지, 커넥션 획득 대기인지 네트워크·S3 응답인지는 가를 수 없다(노드 익스포터에 TCP 재전송 지표 없음). 원인은 미확정.
- 판단: SDK 기본값(Apache 커넥션 50, 획득 대기 10초, 소켓 30초, 시도·호출 상한 없음)에서는 멈춘 연결 한 번이 수 초~30초를 그대로 쓴다. 원인이 어느 쪽이든 한 시도를 짧게 끊고 새 연결로 다시 하면 꼬리가 상한 근처로 잘린다.
- 수정(backend `feat/upload-before-response`): S3 클라이언트에 커넥션 128·획득 대기 1초·연결 1초·소켓 2초·시도 상한 2초·호출 상한 6초·SDK 시도 3회를 명시(설정 `storage.s3.*`). SDK 지표 발행기(`S3CallMetrics`)로 호출마다 `s3.call`(연산·결과·재시도 여부)·`s3.connection.acquire` 히스토그램을 내보내고, 500ms 이상·재시도·실패 호출은 시도별(커넥션 획득·서버 응답·첫 바이트·상태 코드·오류·재시도 전 대기)로 `s3.slow_call` 로그를 남긴다. 업로드 쪽은 500ms 넘는 put 을 키와 함께 `upload.slow_put` 으로 남긴다. C 의 대기 상한 8초·`IMAGE_STORE_FAILED` 는 그대로.
- 재측정 전 예측(작업자 30명 3분, 업로드 풀 코어 6): (1) 수정 전 C6 이미지는 3분 동안 2초 넘는 업로드가 나올 수도, 안 나올 수도 있다(1/3,809 작업 빈도라 3분 1회로는 재현 보장 없음). (2) 수정 후 업로드(병렬 3장) max ≤ 2.2초(멈춘 시도가 2초에서 끊기고 재시도), p99 는 수정 전과 같은 300~350ms. (3) `IMAGE_STORE_FAILED` 0. (4) `s3.connection.acquire` max < 10ms(커넥션 128 이 동시 사용 약 36개보다 넉넉). (5) 재현 보장이 없으므로 멈춘 연결을 흉내 낸 로컬 테스트로 "첫 시도 10초 멈춤 → 2초에서 끊고 재시도해 성공"을 따로 확인한다.
- 09-26 21:27 C 이미지 빌드: git archive b732e51 → `cj-ai-backend:upload-c6s` (96f68e1f81ed, 42초). 소스 EC2 ~/upload-c-src
- 09-26 21:27 backend 0bed710(S3 수정) 커밋, exp/upload-c-core6 를 그 위로 옮김(b732e51). C6S 이미지 `cj-ai-backend:upload-c6s`(96f68e1f81ed) 빌드. postgres-exporter 에 사용자 질의(cjj_measurement_image_rows) 추가·EC2 모니터링 스택 반영, 대시보드 첫 줄을 응답 p95·PENDING·업로드 풀로 재배치. 로컬 S3ClientStallTest: 첫 시도 10초 멈춤 → 수정 설정 2,083ms(시도 2회, 첫 시도 ConfiguredTimeout), SDK 기본값 10,085ms. 이어서 작업자 30명 3분을 C6(수정 전) → C6S(수정 후) 순으로 잰다.
- 09-26 21:33 `m2-C6-v30` 요청 3776 (INFERRED 아님 0 ) p50/p95/p99/max 420/541/561/677ms, 사진 종료 직후 {'STORED': 11328} → 정착 뒤 {'STORED': 11328}, 업로드 풀 활성 최대 6 큐 최대 50 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0, 's3_slow_call_log': 0, 'slow_put_log': 0}, RDS 크레딧 36.6→36.8
- 09-26 21:38 `m2-C6S-v30` 요청 3779 (INFERRED 아님 0 ) p50/p95/p99/max 418/538/557/619ms, 사진 종료 직후 {'STORED': 11337} → 정착 뒤 {'STORED': 11337}, 업로드 풀 활성 최대 6 큐 최대 43 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0, 's3_slow_call_log': 0, 'slow_put_log': 0}, RDS 크레딧 36.8→37.1
- 21:39 재측정 결과(작업자 30명 3분, 같은 순서 C6 → C6S):

  | 지표 | C6 수정 전 | C6S 수정 후 | 예측 |
  | --- | ---: | ---: | --- |
  | 촬영 요청 / INFERRED 아님 | 3,776 / 0 | 3,779 / 0 | - |
  | 응답 p50 / p95 / p99 / max (k6) | 420 / 541 / 561 / 677ms | 418 / 538 / 557 / 619ms | - |
  | 업로드(병렬 3장) p50 / p95 / p99 / max | 99 / 239 / 302 / 401ms | 126 / 232 / 303 / 492ms | max ≤ 2.2초, p99 300~350ms — 일치 |
  | 업로드 대기 max | 68ms | 175ms | - |
  | `IMAGE_STORE_FAILED` · PENDING · FAILED | 0 · 0 · 0 | 0 · 0 · 0 | 0 — 일치 |
  | S3 호출 22,813회: 재시도 · p99 · max(PutObject) | - | 0회 · 54ms · 104ms | - |
  | S3 커넥션 획득 max | - | 21ms | < 10ms — 불일치(21ms, 획득 상한 1초 대비 여유) |
  | `s3.slow_call`·`upload.slow_put` 로그 | - | 0 · 0 | - |

  9.9초 같은 멈춤은 두 실행 모두 다시 나오지 않았다(예측 (1)대로 재현 보장 없음). 실측으로는 "수정 뒤에도 정상 구간 성능이 같다"까지만 확인됐고, 꼬리를 자르는 효과는 로컬 S3ClientStallTest(10초 멈춤 → 2,083ms 성공, 기본값 10,085ms)로 확인했다. 운영에서 다시 멈추면 `s3.slow_call` 줄이 커넥션 획득·서버 응답·오류 종류를 남긴다.

## 후속 2 — 포폴용 도구 화면 (09-26 21:39~)

- 대시보드 첫 줄(응답 p50/p95/p99 · PENDING · 업로드 풀)이 한 화면에 들어가도록 바꿨고 PENDING 은 새 exporter 지표라 과거 조건에는 없다. 같은 레이아웃으로 M4(작업자 60명 3분)를 A → C6 → C6S, M3(작업자 10명, 60초 시점 재시작)를 A → C 로 다시 돈다. 조건마다 k6 콘솔 요약·psql 출력(종료 직후·정착 뒤)·Grafana 캡처를 screens/ 에 남긴다.
- 09-26 21:46 `m4-A` 요청 7590 (INFERRED 아님 0 ) p50/p95/p99/max 416/531/555/778ms, 사진 종료 직후 {'PENDING': 2309, 'STORED': 20461} → 정착 뒤 {'PENDING': 27, 'STORED': 22743}, 업로드 풀 활성 최대 6 큐 최대 1980 CallerRuns , 로그 {'rejected': 18, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0, 's3_slow_call_log': 0, 'slow_put_log': 0}, RDS 크레딧 37.1→37.3
- 09-26 21:46 `m4-A` 재실행이 기존 `m4-A` 디렉터리를 덮어 `m4-A-r2` 로 옮기고 기존 결과를 git 에서 되살렸다. 이후 재실행은 REP 접미사를 붙인다. m4-A-r2: 요청 7,590, p95 531ms, 큐 최대 1,980, 거절 로그 18줄(9건), PENDING 종료 직후 2,309 → 120초 뒤 27장.
- 09-26 21:52 `m4-C6-r2` 요청 7564 (INFERRED 아님 0 ) p50/p95/p99/max 416/532/555/1058ms, 사진 종료 직후 {'STORED': 22692} → 정착 뒤 {'STORED': 22692}, 업로드 풀 활성 최대 6 큐 최대 57 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0, 's3_slow_call_log': 0, 'slow_put_log': 0}, RDS 크레딧 36.9→36.8
- 09-26 21:59 `m4-C6S-r2` 요청 7559 (INFERRED 아님 0 ) p50/p95/p99/max 414/534/571/2372ms, 사진 종료 직후 {'STORED': 22677} → 정착 뒤 {'STORED': 22677}, 업로드 풀 활성 최대 6 큐 최대 39 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0, 's3_slow_call_log': 0, 'slow_put_log': 0}, RDS 크레딧 36.8→36.8
- 09-26 22:05 `m3-A-r2` 요청 1270 (INFERRED 아님 130 {'http_0': 130}) p50/p95/p99/max 428/548/593/2148ms, 사진 종료 직후 {'STORED': 3420} → 정착 뒤 {'STORED': 3420}, 업로드 풀 활성 최대 3 큐 최대 4 CallerRuns , 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0, 's3_slow_call_log': 0, 'slow_put_log': 0}, RDS 크레딧 36.8→37.0
- 09-26 22:10 `m3-C-r2` 요청 1289 (INFERRED 아님 129 {'http_0': 129}) p50/p95/p99/max 421/541/583/2007ms, 사진 종료 직후 {'STORED': 3480} → 정착 뒤 {'STORED': 3480}, 업로드 풀 활성 최대 3 큐 최대 13 CallerRuns 0, 로그 {'rejected': 0, 'caller_runs_log': 0, 'upload_failed_log': 0, 'image_store_failed_log': 0, 's3_slow_call_log': 0, 'slow_put_log': 0}, RDS 크레딧 37.0→37.3
- 22:1x M3 재실행(REP=2, 새 레이아웃·psql 화면): A 요청 1,270·실패 응답 130(http_0)·PENDING 0, C 요청 1,289·실패 응답 129(http_0)·PENDING 0. 1회차와 같다. M4 재실행: A-r2 요청 7,590·p95 531ms·PENDING 종료 직후 2,309(csv)/2,215(psql, 수십 초 뒤) → 120초 뒤 27장·거절 9건, C6-r2 p95 532ms·PENDING 0, C6S-r2 p95 534ms·PENDING 0(max 2,372ms 는 추론 2,162ms, 업로드 무관). 기존 `m4-A` 디렉터리를 덮은 실수는 18:41 행 참조.

## 사고 — 데모 리셋이 풀 실험 데이터를 지움 (09-26)

| 항목 | 내용 |
| --- | --- |
| 시각 | 18:32(m1-A 첫 리셋)부터 22:10(m3-C-r2)까지 조건마다. 22:1x 풀 스윕 준비 중 발견 |
| 원인 | `upload-ab.sh` 가 조건마다 `POST /api/v1/admin/demo/reset` 을 불렀다. 데모 리셋은 주문·배송단위·토트 할당·재고 원장을 시연 초기 상태로 다시 만든다. `fixture-reset.sql` 주석의 "시연 리셋은 쓰지 않는다" 를 확인하지 않았다 |
| 영향 | 풀 크기 실험 묶음(PSFIX- 배송단위 36,000건) 0건, 재고 원장 20,317행 → 21행(max id 3,131,664), 출고 상품 잔고 약 9.4만 → 101~119. 지운 원장 행은 백업이 없어 되살릴 수 없다. 기존 pool-sizing 결과 파일·판정은 영향 없음. upload-ab 측정 자체는 촬영 경로만 쓰므로 결과 영향 없음 |
| 조치 | `upload-ab.sh` 의 리셋을 `measurement_*` 만 지우는 SQL + 추론 워밍 2회로 교체, `upload-ab.sh`·`fixture-reset.sql` 상단에 경고 주석. 출고 상품 8종에 재고 조정 +100,000(멱등 키 `psfix-restock-20260926-<gtin>`, 원장 txId 3131665~3131672), 같은 시드로 묶음 재접수. 원장 컷오프는 재접수 뒤 max(id) 로 새로 잡아 `ledger-reset.sql`·`pool-sweep.env` 에 남김. 자세한 경과는 `docs/evidence/pool-sizing/progress.md` |
- 09-26 22:31 복원: 이미지 cd6222eefbf2(기준 cd6222eefbf2), 촬영 데이터 정리, measurement_image 0행
- 22:5x 종료 상태: 백엔드 이미지 cd6222eefbf2(기준), 실험 설정 흔적 없음, measurement_session 은 촬영 테이블 정리 뒤 남은 행 없음·measurement_image 0행. EC2 에 이미지 `upload-c`·`upload-c6`·`upload-c6s` 와 소스 `~/upload-c-src` 가 남아 있다. 모니터링 스택에 postgres-exporter 사용자 질의(`cjj_measurement_image_rows`)를 추가한 상태로 둔다.
