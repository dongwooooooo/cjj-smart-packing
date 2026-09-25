# 부하 테스트와 모니터링

kciter의 "서버 모니터링 분석 가이드"가 말하는 방식을 따른다. 대시보드는 **증상**(트래픽·지연·에러)을 위에, **원인**(구간별 시간, 포화도)을 아래에 둔다. 판독은 그래프를 겹쳐 놓고 "누가 기다리고 누가 한가한가"를 본다.

## 구성

| 구성 요소 | 위치 | 역할 |
| --- | --- | --- |
| Prometheus + Grafana + node_exporter + postgres_exporter | 백엔드 EC2, compose 프로젝트 `monitoring` | 5초 간격 수집. 백엔드 `/actuator/prometheus`(X-Demo-Key 필요), EC2, RDS |
| 백엔드 Micrometer | `measure.stage{stage=load|infer|save|total}`, `inference.stage{stage=build|invoke|parse}`, `upload.duration`, `inference.failures` | 로그의 timing 구간과 같은 구간을 히스토그램으로 |
| k6 | 부하 발생기 EC2(같은 VPC) | `--out experimental-prometheus-rw` 로 같은 Prometheus 에 씀. 시험 구간은 Grafana 주석 |

접속: Grafana `http://<backend-ip>:3000` (내 IP 만), Prometheus `:9090`. 비밀번호는 `local/grafana.env`.

## 실행

부하 발생기에 `tools/loadtest/` 를 복사한 뒤:

```bash
BASE=http://<backend-private-ip>:8000 PROM=http://<backend-private-ip>:9090 GRAFANA=http://<backend-private-ip>:3000 \
GRAFANA_AUTH=admin:<pw> DEMO_KEY=<key> bash run.sh capture
```

| 시나리오 | 사용자 행동 | 서버 부위 | 판정 |
| --- | --- | --- | --- |
| `capture` | 작업자 1→20명이 입고 화면에서 촬영 버튼을 누른다 | 사진 읽기 → Lambda Invoke → 세션 커밋 → 비동기 S3 업로드 | 촬영 p95 < 1초, 실패 < 1%. Lambda 동시 실행·HikariCP·업로드 executor 중 어디가 먼저 차는가 |
| `orders_import` | 상위 시스템이 N주문 배치를 분당 R건 보낸다 | 검증 → 편성 → 라인·토트 → 저장(한 트랜잭션) | 응답 시간이 주문 수에 선형인가, 동시 배치에서 커넥션·락 대기가 생기는가 |
| `packing` | 포장 작업자 N명이 토트 스캔 → 포장 완료 | 재고 차감, 박스 재고 행 락, 토트 해제 | 완료 p95, 락 대기, OUT_OF_STOCK 은 데이터 소진으로 별도 집계 |

결과는 `results/<run-id>/summary.json`, `k6.log`. Grafana 의 `cjj 부하 테스트` 대시보드에서 시험 구간 주석으로 찾는다.

## 판독 순서

1. 증상 1(k6): p95 가 어느 VU 수에서 꺾이는가. 에러율이 같이 오르면 느려지며 죽는 것, 에러율만 오르면 즉시 실패.
2. 증상 2(서버): k6 지연과 서버 지연의 차이가 곧 네트워크·큐잉. 차이가 벌어지면 Tomcat 스레드를 본다.
3. 원인 1(구간): 촬영이면 load/infer/save 중 어느 구간이 늘었는가. infer 만 늘면 Lambda, save 만 늘면 DB·업로드.
4. 원인 2(포화도): Tomcat busy=max, Hikari pending>0, executor queued>0, CPU>80%, RDS 락 대기 중 무엇이 먼저 차는가.
5. 타임아웃 예산: 촬영 1초 = Invoke p95 + 백엔드 구간 p95 + 여유. 예산을 넘는 구간이 바꿀 대상이다.

## 커넥션 풀·서버 설정 스윕 (`pool-sweep.sh`)

부하를 고정하고 설정 하나만 바꿔 가며 같은 절차로 재는 도구다. Oracle Real World Performance 영상(https://www.youtube.com/watch?v=_C77sBcAtSQ)이 스레드 수와 생각 시간을 고정하고 JDBC 풀 크기만 줄여 가며 TPS·Queue-ms·Run-ms·대기 이벤트를 한 화면에 놓은 방식을 이 시스템에 옮겼다. 조건마다 도구가 자동으로 하는 일:

1. 백엔드 설정 반영: 백엔드 EC2 의 compose 프로젝트에 `docker-compose.pool-sweep.yml`(환경변수 `SPRING_APPLICATION_JSON` 한 줄)을 얹어 컨테이너를 다시 만든다. 이미지는 실험 전 컨테이너의 것 그대로. 헬스 UP 과 `hikaricp_connections_max`·`tomcat_threads_config_max_threads` 로 반영을 확인한다.
2. 데이터 원복: 실험 묶음(주문번호 `PSFIX-`) 배송단위를 포장 전 상태로 되돌린다(`sweep/fixture-reset.sql`). 시연 리셋은 박스 재고를 100 으로 되돌려 쓰지 않는다.
3. 1초 간격 `pg_stat_activity` 표본(`sweep/pg-waits.sql`)을 백엔드 호스트의 psql 컨테이너로 채집 시작.
4. 부하 발생기에서 k6 실행(판독 구간 지표 `measured_*` 는 워밍업 이후만), Grafana 주석(태그 `pool-sweep`).
5. `sweep/collect.py` 가 k6 요약·Prometheus·대기 이벤트 CSV·CloudWatch(RDS CPU)를 모아 `result.json` 을 쓰고 한 줄 출력:
   `pool | VU | pacing | TPS | Queue-ms p95 | Run-ms p95 | http p95 | pending max | top wait`
6. `sweep/capture.py` 가 Grafana 대시보드 `cjj-pool-sizing` 을 판독 구간으로 찍어 `grafana.png` 로 저장.

스윕이 끝나면 `sweep/report.py` 가 전 조건 비교표·판정 규칙 기계 적용·캡션 초안을 `README.md` 로 쓰고, 백엔드를 실험 전 설정으로 복원한다. 오류나 Ctrl-C 로 멈춰도 trap 이 복원한다. 복원 확인은 컨테이너 환경변수에 `SPRING_APPLICATION_JSON` 이 없고 이미지 id 가 기준과 같은지로 한다.

### 전제

- 인프라가 켜져 있다: 백엔드 EC2, RDS, 부하 발생기 EC2, 백엔드 EC2 의 `monitoring` compose(Prometheus·Grafana).
- 보안 그룹이 내 IP 에 22·3000·9090 을 연다(`infra/terraform.tfvars` 의 `my_ip`). IP 가 바뀌면 `curl https://checkip.amazonaws.com` 으로 확인.
- SSH 키 `~/cjj/key.pem`(경로는 `pool-sweep.env` 의 `SSH_KEY`), 호스트 키 고정 파일 `local/known_hosts`(`ssh-keyscan -t ed25519 <ip> >> local/known_hosts`).
- `local/grafana.env` 의 `GRAFANA_ADMIN_PASSWORD`(주석용). 데모 키·DB 접속 정보는 백엔드 EC2 의 `~/backend/.env` 에서 그때그때 읽고 로컬에 저장하지 않는다.
- 로컬 python3 에 `boto3`(RDS CPU, 로컬 AWS 자격증명)와 `playwright`(캡처). 없으면 해당 열만 비고 스윕은 돈다.
- 실험 묶음이 있어야 한다. 처음 한 번 `bash tools/loadtest/pool-sweep.sh fixture 20000`(500건씩 접수, 배치당 약 20~30초). 조작 값은 전부 `pool-sweep.env` 에 있고, 같은 이름의 환경변수로 덮어쓴다.

### 예시

```bash
# 1) 풀 크기 스윕: 피크 1배 부하(작업자 100명, 1분에 1건)에서 풀 5개 크기
POOL_SIZES="2 5 10 20 40" LOADS="peak1x:100:60000:50000:0" bash tools/loadtest/pool-sweep.sh sweep

# 2) 타임아웃 실험: 풀 크기 고정, connectionTimeout 3개, 판독 60초 뒤 박스 행을 20초 잠금, 클라이언트 10초
POOL_SIZES=10 CONN_TIMEOUTS_MS="30000 3000 1000" LOCK_INJECT=60:20 CLIENT_TIMEOUT=10s \
  LOADS="peak3x:300:60000:50000:0" bash tools/loadtest/pool-sweep.sh sweep

# 3) 결정값 재검증: 기본값(10)과 결정값을 같은 부하로 2회씩
POOL_SIZES="10 <결정값>" REPEAT=2 LOADS="peak3x:300:60000:50000:0 sat:<VU>:0:0:0" bash tools/loadtest/pool-sweep.sh sweep
```

한 번에 10분을 넘기면 끊어질 수 있는 환경(원격 세션)에서는 `POOL_SIZES` 를 1~2개씩 나눠 여러 번 부르고, `report` 로 디렉터리를 합쳐 읽는다. 스윕이 멈춘 뒤 복원 여부가 의심되면 `check` 로 확인하고 `restore` 로 되돌린다.

### 결과물

`docs/evidence/pool-sizing/<시각>/` 아래에 `sweep.json`(실행 조건), `console.txt`(화면 출력 행), `README.md`(비교표), 조건별 디렉터리(`meta.json`, `summary.json`·`k6.log`(k6), `waits.csv`(대기 이벤트 1초 표본), `fixture-reset.log`, `lock-inject.log`, `result.json`, `grafana.png`). 조건마다 `docs/evidence/pool-sizing/progress.md` 에 한 줄이 쌓인다.

### 블로그로 옮기기

- 표: 비교표에서 부하 수준 하나를 골라 pool·TPS·Queue-ms·Run-ms·상위 대기 열만 남긴다. 영상의 표와 같은 순서다.
- 캡처: 조건별 `grafana.png` 를 그대로 쓰거나, 표의 "보기" 링크(판독 구간 ±30초)를 열어 패널 하나를 잘라 쓴다.
- 캡션: `README.md` 의 캡션 초안(조건·수치 한 줄)에 "무엇이 왜 문제인지"를 사람이 덧붙인다. 판정 규칙 초안은 기계 적용이라 수치를 확인한 뒤 옮긴다.
