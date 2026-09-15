# 촬영→응답 E2E 구간 실측 (2026-09-14, 로컬 재현)

구성: 백엔드(compose, 프로젝트 cjj-measure, :8010) → AWS SDK Invoke(엔드포인트 오버라이드) → Lambda 컨테이너 이미지(RIE, :9000, N_THREADS=4).
사진: demo 마스터 사진을 cam1~3에 복제. large=3장 490KB(원본), small=3장 57KB(512px).
동시 요청은 RIE가 1건만 받아 패닉 → 단일 스레드 결과만 유효. 같은 맥에서 다른 컨테이너(mysql 53%, kafka 20%)가 CPU를 써서 핸들러 절대치는 흔들림.

| 구간 | large run1 p50/p95 | large run2 p50/p95 | small p50/p95 | 비고 |
|---|---|---|---|---|
| 사진 읽기 loadMs | 6 / 26 | 15 / 40 | — | 로컬 파일. 운영은 S3 GET 3회 — 미측 |
| 이벤트 조립 buildMs | 12 / 105 | 21 / 73 | 2 / 8 | multipart+base64+JSON. 페이로드 비례 |
| Invoke 왕복 invokeMs | 296 / 962 | 757 / 1486 | 242 / 643 | |
| └ 핸들러 elapsed_ms | 258 / 759 | 597 / 1276 | 228 / 549 | 디코드+추론. 노이즈 큼. 운영 기준은 CloudWatch(웜 p50 325 / p95 611) |
| └ 전송·RIE·Mangum | 40 / 240 | 94 / 248 | 16 / 94 | invokeMs − elapsed_ms |
| 응답 파싱 parseMs | 1 / 26 | 8 / 33 | — | |
| 저장 saveMs | 32 / 144 | 81 / 227 | 21 / 120 | 세션 커밋 + 사진 3장 저장. 운영은 S3 put 3회가 TX 안 — 미측 |
| 클라이언트 E2E | 379 / 1250 | 925 / 1770 | 282 / 777 | |
| base64 팽창 | 1.34x (490KB→655KB) | | 1.35x | |

해석
- 백엔드 경로(읽기+조립+파싱+저장+전송) p50 약 90~220ms. 8/26 표본 1개에서 추정한 0.9초는 초기화·첫 호출 효과였음.
- 운영 E2E 추정 = CloudWatch 핸들러(p95 611) + 백엔드 경로(p95 300~500) + S3 GET/put(미측) → p95 0.9~1.1초. 1초 p95 계약은 경계선, p50은 0.5초 안팎.
- 백엔드 쪽 가장 큰 구간은 저장(saveMs)이며 운영에선 S3 put 3장이 트랜잭션 안에 있어 더 커질 수 있음 → 요청 경로 밖(비동기)으로 빼는 것이 백엔드 측 1순위 레버.
- 페이로드 490KB→57KB로 줄여도 조립 10ms·전송 20~80ms 절감 수준. 리사이즈 이전은 2순위.

원본: measure-large-t1-run1.json, measure-large-t1.json(run2), measure-small-t1.json, lambda-report-events.json(CloudWatch 332건).
코드 변경: backend 브랜치 measure/inference-path (endpoint override + 구간 로그, 미푸시).
