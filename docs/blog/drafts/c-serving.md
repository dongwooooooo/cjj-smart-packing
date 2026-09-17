# GPU 전제 8초 계약을 CPU Lambda로 — 치수 추정 모델 서빙 3일

추론 API의 타임아웃 8초는 GPU 개발 파드에서 서빙한다는 전제로 정한 값이었습니다(결정 이력 D-15). 근거는 CPU 실측이었습니다. CPU 추론이 V3 모델 5.87초, V2 모델 17.47초였고, GPU면 그 안에 들어온다는 계산이었습니다. 그런데 시연 환경에는 GPU가 없었습니다. AI 담당은 학습 결과를 torch 형식(`model.safetensors`)으로 Hugging Face 비공개 저장소에 올리는 방식으로 일하고 있었고, 그 절차를 바꿀 시간도 없었습니다. 이 글에서는 서빙 위치를 고른 근거, torch를 ONNX로 바꾸는 일을 이미지 빌드에 넣은 이유, 백엔드 연동에서 만난 네 갈림길, 그리고 시연 기간 호출 332건의 분포를 다룹니다.

## 서빙 위치

Lambda 컨테이너 이미지를 택했습니다. 입고 신규 상품 등록은 상시 트래픽이 아니라 호출당 과금이 맞고, 시연 환경의 GPU 파드는 접근과 가용을 보장받을 수 없었습니다.

| 방식 | 장점 | 기각 사유 |
| --- | --- | --- |
| GPU 개발 파드 | 계약 산정 기준 그대로 | 시연 환경에서 접근·가용 보장 없음. 외부 의존이 요청 경로에 남음 |
| EC2 상시 서버 + torch | 구조 단순, 콜드스타트 없음 | CPU torch 추론 1,070ms. 간헐 트래픽에 상시 비용. 백엔드와 같은 인스턴스에 동거 |
| Lambda 컨테이너 + ONNX Runtime (채택) | 호출당 과금. ONNX로 추론 185ms, 모델 로드 0.22초 | 콜드스타트 관리 필요. zip 배포는 250MB 한도라 컨테이너 이미지(10GB) 필수 |

EC2 안은 처음에 병행 트랙으로 만들었다가 폐기했습니다. 인스턴스가 백엔드 서버로 전환되면서 추론 배포 워크플로가 남아 있으면 8000 포트가 충돌했기 때문입니다.

## torch에서 ONNX로, 그리고 이미지 빌드 안으로

같은 사진 3장 기준으로 추론은 1,070ms에서 185ms로, 모델 로드는 3.10초에서 0.22초로 줄었습니다(macOS, 4스레드, 워밍업 1회 뒤 5회 중앙값). 예측값은 61.6 / 55.8 / 4.0cm로 소수 첫째 자리까지 같았고, 변환 직후 원시 출력 대조에서 max diff는 7.45e-08이었습니다.

변환을 사람이 돌려서 올리는 절차는 만들지 않았습니다. Dockerfile을 변환 스테이지와 런타임 스테이지로 나눠, 이미지 빌드가 safetensors를 받아 ONNX로 바꾸고 결과만 런타임 이미지에 남깁니다.

| 스테이지 | 베이스 | 하는 일 | 최종 이미지에 남는가 |
| --- | --- | --- | --- |
| builder | python:3.12-slim | torch 설치, Hugging Face에서 safetensors 다운로드, ONNX 변환, torch 출력과 대조 | 아니오 |
| runtime | public.ecr.aws/lambda/python:3.12 | onnxruntime만 설치, `model.onnx`와 `config.json`만 받아 서비스 | 예 |

이 구조로 세 가지가 정해집니다. AI 담당은 지금처럼 safetensors만 올리면 됩니다. torch와 원본 가중치는 최종 이미지에 들어가지 않습니다. Hugging Face 토큰은 BuildKit secret mount로만 전달해 이미지 레이어와 `docker history`에 남지 않습니다. `ARG`나 `ENV`로 받으면 ECR 이미지를 pull할 수 있는 누구나 토큰을 읽을 수 있습니다.

변환이 어긋나면 빌드가 그 자리에서 멈춥니다. 변환 직후 같은 입력을 torch 모델과 ONNX 세션에 넣고 출력을 비교합니다.

```python
diff = float(np.abs(ref - got).max())
print(f"[export] {out.name} {size_mb:.1f}MB, torch 대비 max diff {diff:.2e}")
# NaN이면 아래 비교가 False가 되어 실패로 떨어진다 (diff > tol 로 쓰면 통과해버린다).
if not diff <= tolerance:                                    # tolerance = 1e-4
    raise SystemExit(f"[export] 실패: max diff {diff:.2e} > 허용치 {tolerance:.0e}.")
```

비교 조건을 `diff > tol`이 아니라 `not diff <= tol`로 쓴 이유는 주석에 있습니다. 변환이 깨져 NaN이 나오면 `diff > tol`은 False라 통과해 버립니다.

## 백엔드 연동의 네 갈림길

백엔드가 들고 있던 잠정 계약과 실제 Lambda API는 거의 모든 항목에서 달랐습니다.

| 항목 | 백엔드 잠정 계약 | 실제 Lambda |
| --- | --- | --- |
| 요청 | JSON `{productId, gtin}` | multipart `images` 3장 + `views` |
| 이미지 출처 | 없음(경로 문자열만 기록) | 필수. 3장 아니면 400 |
| 인증 | 없음 | `X-API-Key` 헤더 + IAM `lambda:InvokeFunction` |
| 통로 | HTTP | SDK Invoke, API Gateway v2 이벤트 형식, body base64 |
| 응답 | `widthCm, lengthCm, heightCm, confidence` | `length, width, height, views_used, warnings, elapsed_ms`. confidence 없음 |
| 타임아웃 | 8초 | 웜 0.3~0.5초, 콜드 약 10초 |

여기서 결정할 것이 넷이었습니다.

**이미지 출처.** 프론트가 사진 3장을 첨부하는 안(계약이 JSON에서 multipart로 바뀜), 백엔드가 상품별 사진을 보관해 그것으로 호출하는 안, 둘의 혼합 중 두 번째를 택했습니다. 프론트에 촬영·업로드 화면이 없었고, 시연 상품의 사진은 시연 데이터 서브시스템이 이미 관리하고 있었습니다. 사진이 없으면 `MEASURE_FAILED(NO_IMAGES)`로 끝냅니다.

**호출 통로.** 공개 URL을 두지 않았습니다. 백엔드가 EC2 인스턴스 프로파일로 AWS SDK `Invoke`를 호출하고, API Gateway v2 형식의 이벤트 JSON(multipart body를 base64로)을 직접 조립합니다. AWS 리소스 변경이 없고 저장된 자격증명이 없습니다. Function URL에 IAM 인증을 붙이는 안은 SigV4 서명 의존과 권한 추가가 필요했고, 인증 없는 Function URL은 주소를 아는 누구나 호출할 수 있어 기각했습니다.

**confidence 부재.** 모델은 신뢰도를 내보내지 않습니다. 표본 958개로는 구간별 확률표가 불안정해 학습 담당이 의도적으로 뺐습니다. 응답 필드는 유지하되 null을 허용하고, null이면 저신뢰 판정을 건너뜁니다. `views_used`나 `warnings`로 대체값을 만드는 안은 근거 없는 숫자를 신뢰도로 보여주는 것이라 기각했습니다.

**콜드스타트 10초 대 계약 8초.** 첫 호출은 모델 로드까지 약 10초로 계약을 넘겼습니다.

| 방식 | 결과 | 기각 사유 |
| --- | --- | --- |
| 타임아웃 상향(8초 → 15초) | 첫 호출도 성공 | 시연 첫 촬영의 10초 대기가 화면에 그대로 보임 |
| 백엔드 주기 워밍 핑 | AWS 변경 없음 | 환경 교체 시 보장 없음. 백엔드 기동 직후 첫 호출은 콜드 |
| Provisioned concurrency 상시 1 | 콜드스타트 제거 | 유휴 과금 월 약 32달러(3,008MB 상시, 미국 동부 단가) |
| 시연 시간대만 Provisioned concurrency 예약 (채택) | 계약 8초 유지, 시연 시간 외 비용 0 | 버전 발행·별칭·Application Auto Scaling 예약 액션 관리 |

Application Auto Scaling의 예약 액션 두 개로 시연 당일 08:50에 1로 올리고 17:00에 0으로 내렸습니다. 함수 메모리는 3,008MB입니다. 10,240MB로 올리려 했으나 계정 쿼터가 3,008MB였고 증설은 Support 케이스가 필요했습니다.

## 배포 자동화와 백엔드 쪽 두 가지 수정

배포는 GitHub Actions가 OIDC로 AWS 역할을 위임받아 ECR push, Lambda 코드 갱신, `live` 별칭 이동까지 자동으로 합니다. 액세스 키를 저장소에 두지 않습니다. 여기서 한 번 막혔습니다. 신뢰 정책에 `repo:cj-ai-sw/ai:*`를 넣었는데 `Not authorized to perform sts:AssumeRoleWithWebIdentity`가 났습니다. 이 조직의 토큰은 `sub` 클레임이 `repo:cj-ai-sw@316033991/ai@1340552961:ref:...`처럼 소유자 ID와 저장소 ID가 붙은 형식으로 발급됐습니다. 이름형과 ID형을 둘 다 넣어야 매칭됩니다.

백엔드 배포도 같은 방식입니다. 인스턴스에 SSH 포트를 열지 않고, 러너가 SSM Run Command로 명령을 보내면 Ubuntu AMI에 들어 있는 SSM 에이전트가 실행합니다. 처음에는 인스턴스가 매 배포마다 Gradle 빌드를 돌렸는데, 빌드가 몇 분씩 시연 서버를 붙잡았고 실패해도 돌아갈 아티팩트가 없었습니다. 이미지 빌드를 CI로 옮기고 인스턴스는 ECR에서 pull만 하도록 바꿨습니다. 헬스가 잡히지 않으면 직전 이미지로 되돌립니다.

백엔드 코드에는 두 가지를 고쳤습니다. 첫째, 추론 호출을 트랜잭션 밖으로 뺐습니다. 콜드스타트 10초 동안 DB 커넥션을 잡고 있을 이유가 없습니다. 측정 저장을 별도 빈으로 분리해 트랜잭션 경계가 실제로 생기게 했습니다. 같은 빈 안의 내부 호출은 프록시를 타지 않아 경계가 생기지 않습니다. 세션은 결과 상태로 한 번에 만들어지므로 순서를 바꿔도 중간 상태가 생기지 않습니다. 둘째, 프론트를 Vercel로 옮기면서 백엔드가 인터넷에 노출되자 모든 요청에 공유 키(`X-Demo-Key`)를 요구하는 필터를 넣었습니다. 키는 프론트가 서버 사이드에서만 붙이고, 실패 응답은 경로를 되돌려주지 않습니다. 헬스체크만 열어 둡니다.

## 시연 기간 호출 332건

EC2 실서버에서 처음 확인한 E2E는 2.6초였습니다. Lambda 초기화 1.2초와 핸들러 0.5초가 들어 있고, 핸들러 로그는 `views_used=3 elapsed_ms=473`이었습니다. 시연 기간(8월 25일~31일) CloudWatch에 남은 호출 332건의 분포는 다음과 같습니다.

| 구분 | 건수 | p50 | p95 | p99 | 최대 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 웜 호출 처리 시간 | 250 | 325ms | 611ms | 654ms | 695ms |
| 콜드 호출 초기화 시간 | 80 | 1.2초 | | | |

최대 메모리 사용은 877MB로 3,008MB 설정의 3분의 1입니다. 메모리를 올린 이유는 용량이 아니라 vCPU 배정입니다. Lambda는 메모리에 비례해 vCPU를 배정하고(1,769MB당 1개), 3,008MB에서 약 1.7개입니다. `N_THREADS`는 이 값에 맞춰 2로 둡니다. 배정보다 스레드가 많으면 서로 CPU를 뺏어 느려집니다.

## 남은 것

8초 계약은 지켰지만 기준으로는 의미가 없어졌습니다. 웜 p95가 611ms인 시스템에 8초 타임아웃은 실패 판정 기준일 뿐, 작업자가 촬영 버튼을 누르고 기다리는 시간의 목표가 아닙니다. 계약을 1초로 다시 정하고 구간별로 잰 이야기는 다음 글에서 다룹니다.

동시 촬영은 재지 못했습니다. 시연은 작업자 한 명이 순차로 촬영하는 구성이었습니다. 3,008MB 쿼터는 증설 신청을 하지 않았습니다. 콜드스타트는 시연 시간대 예약으로 피했을 뿐 없앤 것이 아닙니다.

코드는 [cjj-smart-packing-ai](https://github.com/dongwooooooo/cjj-smart-packing-ai)의 `inference/`, `deploy/lambda/`, `.github/workflows/`에 있고, 백엔드 호출부는 [cjj-smart-packing-backend](https://github.com/dongwooooooo/cjj-smart-packing-backend)의 `inbound/service/LambdaInferenceClient.java`입니다.

---

참고

- AWS, [Create a Lambda function using a container image](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html) — zip 250MB, 컨테이너 이미지 10GB 한도
- AWS, [Configuring provisioned concurrency](https://docs.aws.amazon.com/lambda/latest/dg/provisioned-concurrency.html) — Application Auto Scaling 예약 액션
- GitHub, [Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) — `sub` 클레임 형식
