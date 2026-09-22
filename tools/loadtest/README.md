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
