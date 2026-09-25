# 풀 크기 실험 진행 기록

시각은 KST. 도구 `tools/loadtest/pool-sweep.sh` 가 조건마다 한 줄씩 자동으로 덧붙인다(형식: 조건 id, 화면 출력 행, k6 종료 코드).

- 09-25 16:0x 접속 시도: `ssh ubuntu@13.124.19.3`, `ssh ubuntu@43.203.152.223` 모두 `connect to host ... port 22: Operation timed out`. Prometheus :9090, Grafana :3000 도 응답 없음(curl exit 28). API :8000 은 200. 원인: 보안 그룹 허용 IP(terraform `my_ip`=58.233.240.191)와 현재 공인 IP(58.151.41.67) 불일치. 로컬 `aws` CLI 는 python3.14 pyexpat 심볼 오류로 실행 불가. 인프라 변경 금지 조건이라 직접 고치지 않고 보고함.
- 09-25 16:1x 사용자가 `my_ip` 갱신 후 apply. SSH 재시도 시 13.124.19.3 호스트 키 불일치 경고. terraform state 의 인스턴스가 `i-0e28d00c1cac39d04`(교체된 인스턴스)이고 접속 후 IMDS 인스턴스 id 가 같아 교체에 따른 키 변경으로 판단. `~/.ssh/known_hosts` 는 건드리지 않고 `local/known_hosts` 에 두 호스트 키를 고정해 사용.
- 09-25 16:1x 기준 상태: 백엔드 컨테이너 이미지 `cj-ai-backend:latest`(id cd6222eefbf2), main f87a37e, `SPRING_APPLICATION_JSON` 없음, hikari max 10, tomcat max 200. RDS PostgreSQL 18.3, `max_connections`=79, 평시 연결 20. 박스 재고 약 4.8~5.0만/종, 상품 잔고 약 9.4만/종, IDLE 토트 35,424.
- 09-25 16:15 스윕 시작 `20260925-161457` pools=[10] timeouts=[30000] threads=[200] loads=[smoke:20:0:0:1000] repeat=1 lock=[]
- 09-25 16:15 스윕 시작 `20260925-161551` pools=[10] timeouts=[30000] threads=[200] loads=[smoke:20:0:0:1000] repeat=1 lock=[]
- 09-25 16:17 `smoke-p10-t30000-th200-r1` pool  10 | VU   20 | pacing      0 | TPS    19.2 | Queue-ms p95     0.1 | Run-ms p95    44.4 | http p95    52.4 | pending max    0 | top wait IdleInTx:app(0.9) (rc=0)
- 09-25 16:17 스윕 종료 `20260925-161551`, 백엔드 기준 설정으로 복원
- 09-25 16:15 첫 스윕 `20260925-161457` 은 `fixture-reset.sql` 마지막 조회의 `status` 모호성 오류로 조건 시작 전에 멈췄고, trap 이 백엔드를 기준 설정으로 복원했다(복원 확인 로그: SPRING_APPLICATION_JSON 없음, 이미지 cd6222eefbf2 일치). SQL 수정 후 재실행한 `20260925-161551` 이 smoke 성공 건이다.
- 09-25 16:1x~16:4x 실험 묶음(주문번호 `PSFIX-`) 출고지시 20,000건 접수(500건 × 40배치, 배치당 19~29초, 거절 0). 배송단위 20,000건, 전부 TOTE_ASSIGNED.
- 09-25 17:30 `pool-sweep.sh check` 실패: `ssh: connect to host 13.124.19.3 port 22: Operation timed out`, Prometheus :9090 curl exit 28. 맥 공인 IP 가 58.233.240.191 로 다시 바뀌어 보안 그룹(58.151.41.67 허용)과 어긋남. :8000 API 는 200. 사용자에게 SG 갱신 요청, 그동안 접속 없이 가능한 작업(도구 커밋, PLAN.md, 백엔드 브랜치) 진행.
- 09-25 17:33 backend 브랜치 feat/hikari-pool-sizing f9f956e 커밋(히스토그램 설정 + HikariMetricsHistogramIT, 설정 제거 시 실패 확인). 실험 중 EC2 에는 같은 키를 SPRING_APPLICATION_JSON 으로 넣는다(배포 이미지는 main f87a37e 그대로). PLAN.md 작성.
