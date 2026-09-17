# GPU 전제 8초 계약을 CPU Lambda로 옮긴 치수 추정 서빙

치수 추정 모델은 카메라 3대가 찍은 사진 3장을 받아 상품의 가로·세로·높이를 cm로 돌려줍니다. 이 추론 API의 타임아웃은 8초입니다. CPU 실측 5.87초를 근거로 삼되, GPU 개발 파드에서 서빙한다는 전제로 정했습니다. 그런데 시연 환경에는 GPU가 없었습니다. AI 담당은 PyTorch로 학습한 가중치를 safetensors 형식(`model.safetensors`)으로 Hugging Face 비공개 저장소에 올리는 방식으로 일하고 있었고, 그 절차를 바꿀 시간도 없었습니다. 이 글에서는 서빙 위치를 고른 근거부터 시연 기간 호출 319건의 분포까지를 다룹니다.

## 서빙 위치

Lambda 컨테이너 이미지를 택했습니다. 추론 엔진은 ONNX Runtime(Open Neural Network Exchange 형식의 모델을 실행하는 런타임)입니다. 실행 환경을 새로 만들고 초기화를 거치는 첫 호출을 콜드스타트라고 하고, 이미 초기화된 환경을 재사용하는 호출을 웜 호출이라고 합니다. 입고 신규 상품 등록은 상시 트래픽이 아니라 간헐 호출이라 호출당 과금이 맞습니다. 시연 환경의 GPU 파드는 접근과 가용을 보장받을 수 없었습니다.

| 방식 | 장점 | 기각 사유 |
| --- | --- | --- |
| GPU 개발 파드 | 계약 산정 기준 그대로 | 시연 환경에서 접근·가용 보장 없음. 외부 의존이 요청 경로에 남음 |
| EC2 상시 서버 + PyTorch | 구조 단순, 콜드스타트 없음 | CPU PyTorch 추론 1,070ms(macOS 로컬, 4스레드). 간헐 트래픽에 상시 비용. 백엔드와 같은 인스턴스에 동거 |
| Lambda 컨테이너 + ONNX Runtime (채택) | 호출당 과금. 시연 기간 웜 호출 p50 325ms | 콜드스타트 관리 필요. zip 배포는 250MB 한도라 컨테이너 이미지(10GB) 필수 |

ONNX Runtime으로 바꾼 효과는 로컬에서 먼저 확인했습니다. 같은 사진 3장 기준으로 추론은 1,070ms에서 185ms로, 모델 로드는 3.10초에서 0.22초로 줄었습니다(macOS, 4스레드, 워밍업 1회 뒤 5회 중앙값). 예측값은 61.6 / 55.8 / 4.0cm로 소수 첫째 자리까지 같았고, 변환 직후 원시 출력 대조에서 max diff는 7.45e-08이었습니다.

이 선택이 성립하는 조건은 둘입니다. 호출이 간헐적이라 상시 서버의 유휴 시간이 길고, 콜드스타트를 허용하거나 피할 수단이 있어야 합니다. 초당 수십 건이 상시로 들어오거나 첫 호출 지연을 절대 허용할 수 없다면 EC2 상시 서버가 맞습니다.

EC2 안은 처음에 병행 트랙으로 만들었다가 폐기했습니다. 인스턴스가 백엔드 서버로 전환되면서, 추론 배포 워크플로를 남겨 두면 8000 포트가 충돌하는 상태가 됐기 때문입니다. safetensors 업로드 절차는 그대로 둔 채, 변환을 누가 언제 할지만 정하면 됐습니다.

## 변환 시점과 이미지 빌드 단계

변환을 사람이 돌려서 올리는 절차는 만들지 않았습니다. Dockerfile을 변환 스테이지와 런타임 스테이지로 나눠, 이미지 빌드가 safetensors를 받아 ONNX로 바꾸고 결과만 런타임 이미지에 남깁니다.

| 스테이지 | 베이스 | 하는 일 | 최종 이미지에 남는가 |
| --- | --- | --- | --- |
| builder | python:3.12-slim | PyTorch 설치, Hugging Face에서 safetensors 다운로드, ONNX 변환, torch 출력과 대조 | 아니오 |
| runtime | public.ecr.aws/lambda/python:3.12 | onnxruntime만 설치, `model.onnx`와 `config.json`만 받아 서비스 | 예 |

이 구조로 세 가지가 정해집니다. AI 담당은 지금처럼 safetensors만 올리면 됩니다. PyTorch와 원본 가중치는 최종 이미지에 들어가지 않습니다. Hugging Face 토큰은 BuildKit secret mount로만 전달해 이미지 레이어와 `docker history`에 남지 않습니다. `ARG`나 `ENV`로 받으면 Amazon Elastic Container Registry(ECR) 이미지를 pull할 수 있는 누구나 토큰을 읽을 수 있습니다.

변환이 어긋나면 빌드가 그 자리에서 멈춥니다. 변환 직후 같은 입력을 PyTorch 모델과 ONNX 세션에 넣고 출력을 비교합니다.

```python
diff = float(np.abs(ref - got).max())
print(f"[export] {out.name} {size_mb:.1f}MB, torch 대비 max diff {diff:.2e}")
# NaN이면 아래 비교가 False가 되어 실패로 떨어진다 (diff > tol 로 쓰면 통과해버린다).
if not diff <= tolerance:                                    # tolerance = 1e-4
    raise SystemExit(f"[export] 실패: max diff {diff:.2e} > 허용치 {tolerance:.0e}.")
```

변환이 깨져 NaN이 나오면 `diff > tolerance`는 False가 되어 통과합니다. 그래서 `not diff <= tolerance`로 썼습니다.

## 백엔드 계약과 실제 API의 차이

백엔드(Spring Boot 서버)의 잠정 계약과 실제 Lambda API는 형식이 전부 달랐습니다.

| 항목 | 백엔드 잠정 계약 | 실제 Lambda |
| --- | --- | --- |
| 요청 | JSON `{productId, gtin}` | multipart `images` 3장 + `views` |
| 이미지 출처 | 없음(경로 문자열만 기록) | 필수. 3장 아니면 400 |
| 인증 | 없음 | `X-API-Key` 헤더 + IAM `lambda:InvokeFunction` |
| 통로 | HTTP | SDK Invoke, API Gateway HTTP API 페이로드 형식 2.0, body base64 |
| 응답 | `widthCm, lengthCm, heightCm, confidence` | `length, width, height, views_used, warnings, elapsed_ms`. confidence 없음 |

형식에서 결정할 것이 셋이었습니다.

**이미지 출처.** 선택지는 셋이었습니다. 프론트가 사진 3장을 첨부하는 안, 백엔드가 상품별 사진을 보관해 호출하는 안, 둘의 혼합입니다. 두 번째를 택했습니다. 첫 번째 안은 계약을 JSON에서 `multipart/form-data`로 바꿔야 했습니다. 프론트에 촬영·업로드 화면이 없었고, 시연 상품의 사진은 시연 데이터 서브시스템(시연용 상품·주문·사진을 적재하고 리셋하는 Spring 서버 안의 모듈)이 이미 관리하고 있었습니다. 촬영과 무관한 고정 사진이라 재촬영해도 결과가 같습니다. 사진이 없으면 `MEASURE_FAILED(NO_IMAGES)`로 끝냅니다.

**호출 통로.** 공개 URL을 두지 않았습니다. 백엔드가 EC2 인스턴스 프로파일로 AWS SDK `Invoke`를 호출하고, API Gateway HTTP API 페이로드 형식 2.0을 따르는 이벤트 JSON을 직접 조립합니다(API Gateway는 경로에 두지 않고 형식만 맞춥니다. multipart body는 base64로 넣습니다). AWS 리소스 변경이 없고 저장된 자격증명이 없습니다. Function URL에 IAM 인증을 붙이는 안은 AWS Signature Version 4(SigV4) 서명을 요청마다 계산해야 하고 권한 추가가 필요했고, 인증 없는 Function URL은 주소를 아는 누구나 호출할 수 있어 기각했습니다.

**confidence 부재.** 모델은 신뢰도를 내보내지 않습니다. 표본 958개로는 구간별 확률표가 불안정해 학습 담당이 의도적으로 뺐습니다. 응답 필드는 유지하되 null을 허용하고, null이면 저신뢰 판정을 건너뜁니다. `views_used`나 `warnings`로 대체값을 만드는 안은 근거 없는 숫자를 신뢰도로 보여주는 것이라 기각했습니다.

## 콜드스타트와 8초 계약

첫 호출은 계약을 넘겼습니다. 설계 시점의 추정은 모델 로드까지 약 10초였습니다. 8월 25일 실서버 첫 호출은 4.9초, 웜 호출은 300~500ms였습니다. 그대로 두면 시연 첫 촬영이 실패 화면으로 끝납니다. Provisioned Concurrency는 호출 전에 실행 환경을 미리 초기화해 두는 Lambda 기능입니다.

| 방식 | 결과 | 기각 사유 |
| --- | --- | --- |
| 타임아웃 상향(8초 → 15초) | 첫 호출 성공 가능성 상승 | 시연 첫 촬영의 긴 대기가 화면에 그대로 보임 |
| 백엔드 주기 워밍 핑 | AWS 변경 없음 | 환경 교체 시 보장 없음. 백엔드 기동 직후 첫 호출은 콜드 호출 |
| Provisioned Concurrency 상시 1 | 콜드스타트 제거 | 3,008MB 실행 환경 하나를 상시 과금 |
| 시연 시간대만 Provisioned Concurrency 예약 (채택) | 계약 8초 유지, 시연 시간 외 비용 0 | 버전 발행·별칭·Application Auto Scaling 예약 액션 관리 |

Application Auto Scaling의 예약 액션 두 개로 시연 당일 08:50에 1로 올리고 17:00에 0으로 내렸습니다.

함수 메모리는 3,008MB입니다. 메모리를 올린 이유는 용량이 아니라 vCPU 배정입니다. Lambda는 메모리에 비례해 vCPU를 배정하고, 1,769MB에서 1개입니다. 3,008MB면 약 1.7개라 환경변수 `N_THREADS`(ONNX Runtime 세션의 intra-op 스레드 수)는 올림한 2로 뒀습니다. 배정보다 스레드가 많으면 서로 CPU를 뺏어 느려집니다. 10,240MB로 올리면 약 6개까지 배정되지만, 당시 확인한 계정 쿼터가 3,008MB였고 증설은 Support 케이스를 거쳐야 해서 신청하지 않았습니다.

백엔드 쪽에서는 추론 호출을 트랜잭션 밖으로 뺐습니다. 콜드 호출이 몇 초씩 걸리는 동안 DB 커넥션을 잡고 있을 이유가 없습니다. 측정 저장을 별도 빈으로 분리해 트랜잭션 경계가 실제로 생기게 했습니다. 같은 빈 안의 내부 호출은 프록시를 타지 않아 경계가 생기지 않습니다. 세션은 결과 상태로 한 번에 만들어지므로 순서를 바꿔도 중간 상태가 생기지 않습니다.

## 배포 파이프라인에서 막힌 지점

배포는 GitHub Actions가 OpenID Connect(OIDC) 토큰으로 IAM 역할을 맡아(AssumeRole) 임시 자격증명을 받고, ECR push, Lambda 코드 갱신, `live` 별칭 이동까지 자동으로 합니다. 액세스 키를 저장소에 두지 않습니다. 신뢰 정책에 `repo:cj-ai-sw/ai:*`를 넣었더니 `Not authorized to perform sts:AssumeRoleWithWebIdentity`가 반환됐습니다. 8월 25일 토큰을 직접 디코드해 보니 이 조직의 `sub` 클레임은 `repo:cj-ai-sw@316033991/ai@1340552961:ref:...`처럼 소유자 ID와 저장소 ID가 붙은 형식이었습니다. 이름형과 ID형을 둘 다 넣어야 매칭됩니다.

## 시연 기간 호출 319건

8월 26일 이후 웜 호출 246건의 처리 시간(CloudWatch `Duration`, 핸들러 실행 구간)은 p50 325ms, p95 609ms, 최대 695ms로 8초 계약 안에 들어왔습니다. 8초를 넘긴 호출은 8월 25일 배포 검증 중 3건뿐이었고, 시연 당일 73건에는 초과가 없었습니다.

CloudWatch 로그 이벤트 332건 중 실제 호출은 319건입니다(나머지 13건은 초기화 단독 이벤트). 입력은 상품별 고정 시드 사진 3장이고, 백분위는 nearest-rank로 계산했습니다.

| 구분 | 건수 | p50 | p95 | p99 | 최대 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 웜 호출 처리 시간 (8월 26일 이후) | 246 | 325ms | 609ms | 652ms | 695ms |
| 콜드 호출 초기화 시간(`Init Duration`, 전 기간) | 67 | 1.2초 | 2.1초 | | 9.5초 |
| 시연 당일 웜 호출 | 71 | 318ms | 596ms | | 695ms |

8월 25일 배포 검증일의 웜 6건을 넣으면 최대값이 30.4초로 뜁니다. 첫 배포 직후 함수 갱신과 겹친 호출이며, 그날의 초기화 3건은 9.3~9.5초로 Lambda 초기화 상한 10초 근처였습니다. 시연 당일은 콜드 호출이 2건뿐이고 초기화 최대 1.3초였습니다. 시연 시간대 Provisioned Concurrency 예약으로 첫 호출이 웜으로 처리됐습니다.

실서버에서 처음 확인한 end-to-end(E2E, 백엔드가 요청을 받은 시점부터 응답을 저장할 때까지) 한 건은 2.6초였습니다. Lambda 초기화 1.2초와 핸들러 실행 시간 0.5초를 빼면 0.9초가 남습니다. 이 0.9초는 백엔드 구간에서 쓴 시간입니다. 사진을 읽고 이벤트를 조립하는 시간, Invoke 왕복을 기다린 시간, 응답을 저장한 시간이 여기 들어 있습니다. 구간별로는 재지 않았습니다.

최대 메모리 사용은 877MB로 설정 3,008MB의 29%입니다. 메모리 설정은 vCPU 배정을 결정하므로, 사용량이 낮다고 내리면 스레드 배정이 줄어 느려집니다.

## 남은 것

타임아웃은 실패 판정 기준이고, 작업자가 기다리는 시간의 목표는 따로 정해야 합니다. 웜 p95가 609ms인 시스템에 8초 타임아웃은 기준으로 의미가 없습니다. 계약을 1초로 다시 정하고 백엔드 구간까지 잰 이야기는 다음 글에서 다룹니다.

같은 구성을 쓰는 시스템이라면 세 가지를 점검할 수 있습니다.

1. 타임아웃이 실패 판정 기준인지 체감 목표인지
2. 콜드 호출의 비율과 초기화 시간을 로그에서 분리해 보고 있는지
3. Provisioned Concurrency 예약이 행사 뒤에도 남아 과금되고 있지 않은지

동시 촬영은 재지 못했습니다. 시연은 작업자 한 명이 순차로 촬영하는 구성이었습니다. 콜드스타트는 시연 시간대 예약으로 피했을 뿐 없앤 것이 아닙니다.

코드는 [cjj-smart-packing-ai](https://github.com/dongwooooooo/cjj-smart-packing-ai)의 `inference/`, `deploy/lambda/`, `.github/workflows/`에 있고, 백엔드 호출부는 [cjj-smart-packing-backend](https://github.com/dongwooooooo/cjj-smart-packing-backend)의 `inbound/service/LambdaInferenceClient.java`입니다.

---

참고

- AWS, [Create a Lambda function using a container image](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html) — zip 250MB, 컨테이너 이미지 10GB 한도
- AWS, [Configure Lambda function memory](https://docs.aws.amazon.com/lambda/latest/dg/configuration-memory.html) — 1,769MB에서 vCPU 1개
- AWS, [Configuring provisioned concurrency](https://docs.aws.amazon.com/lambda/latest/dg/provisioned-concurrency.html) — Application Auto Scaling 예약 액션
- GitHub, [Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) — `sub` 클레임의 표준 형식. ID형은 2026-08-25 토큰 실측
