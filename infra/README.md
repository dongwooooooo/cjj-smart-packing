# infra — 개인 계정 운영 인프라 (Terraform)

계정 300390308149(ap-northeast-2), 기본 VPC. 팀 시연 때 손으로 만들었던 구성을 코드로 옮긴 것이다. 상태 파일은 로컬(`terraform.tfstate`, git 제외)이며 DB 비밀번호·API 키가 들어 있으므로 다른 곳에 복사하지 않는다.

## 구성

| 자원 | 이름 | 비고 |
| --- | --- | --- |
| EC2 | `cjj-backend` (c7i-flex.large, Ubuntu 24.04) | docker compose 로 백엔드 실행. 배포는 SSM. 기존 탄력적 IP 13.124.19.3 재사용 |
| RDS | `cjj-postgres` (PostgreSQL 18, db.t4g.micro, 20GB) | 비공개. 백엔드 SG 에서만 5432 |
| S3 | `cjj-images-<계정>`, `cjj-eval-data-<계정>` | 촬영·시연 사진 / 게이트 평가 데이터. 둘 다 비공개 |
| ECR | `cj-ai-backend`, `logistics-dimension-api` | 워크플로의 `ECR_REPO` 값 그대로. 최근 10개 유지 |
| Lambda | `logistics-dimension-api` + 별칭 `live` | 컨테이너 이미지, 3,008MB, 60초, `N_THREADS=2`. 이미지 push 뒤 2차 apply 에서 생성 |
| IAM | `cjj-github-actions`(OIDC), `cjj-backend-ec2`(인스턴스 프로파일), `cjj-dimension-lambda-exec` | 이전 역할(`github-actions-logistics-dimension`, `ec2-invoke-dimension-lambda*`, `logistics-dimension-lambda-exec`)은 건드리지 않는다. 확인 후 손으로 삭제 |

기본 VPC 의 서브넷 4개는 IGW 경로가 없는 라우트 테이블에 명시 연결돼 있다(계정 상태, 2026-09-16 확인). `network.tf` 가 그 테이블에 `0.0.0.0/0 → IGW` 경로를 추가한다. 이 경로 없이는 인스턴스가 apt·SSM·SSH 전부 불통이다.

CloudWatch 로그 그룹 `/aws/lambda/logistics-dimension-api` 는 시연 기간 호출 기록이 남아 있어 terraform 으로 관리하지 않는다. 삭제 금지.

## 절차

### 0. IAM 사용자 권한 (1회)

`awesome` 사용자에게 RDS·S3 권한이 없다(2026-09-16 확인: `rds:DescribeDBInstances`, `s3:ListAllMyBuckets` 거부). apply 전에 붙인다.

```bash
aws iam attach-user-policy --user-name awesome --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess
aws iam attach-user-policy --user-name awesome --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### 1. 1차 apply — Lambda 제외 전부

```bash
cp terraform.tfvars.example terraform.tfvars   # my_ip 를 현재 IP 로
terraform init
terraform apply
```

### 2. 추론 이미지 push

`ai/deploy/lambda/build_push.sh` 가 ECR 에 push 한다. HF 토큰은 BuildKit secret 으로만 넘긴다.

```bash
cd ../ai && AWS_ACCOUNT_ID=300390308149 bash deploy/lambda/build_push.sh
```

### 3. 2차 apply — Lambda 생성

```bash
terraform apply -var lambda_enabled=true -var lambda_image_tag=<push 한 태그>
```

### 4. GitHub Actions 연결 (2026-09-16 완료)

`terraform output github_setup` 이 출력하는 `gh secret set` / `gh variable set` 명령을 실행한다. 이어서 공개 저장소 워크플로를 고친다.

- backend `build-push.yml`·`deploy-ec2.yml`: 트리거 브랜치 `develop` → `main`, `DEFAULT_INSTANCE_ID` 는 저장소 변수 `EC2_INSTANCE_ID` 로 대체
- ai `build-deploy.yml`: 변경 없음 (main 트리거)

### 5. 확인 (2026-09-16: 헬스 UP, 리셋→스캔→측정 E2E 통과)

```bash
aws ssm describe-instance-information --query 'InstanceInformationList[].[InstanceId,PingStatus]' --output text
curl -s http://$(terraform output -raw backend_public_ip):8000/actuator/health
```

프론트(Vercel)에는 `terraform output -raw demo_api_key` 값과 백엔드 주소를 환경변수로 넣는다.

## 작업 없는 날

```bash
bash tools/infra/pause.sh    # EC2 중지 + RDS 중지 (RDS 는 7일 뒤 자동 재시작)
bash tools/infra/resume.sh   # RDS 시작 → EC2 시작 → 헬스 확인
```

중지 중에도 EIP(연결 상태)·EBS·RDS 스토리지는 과금된다. 이전 IAM 역할 4개는 그대로 둔다(2026-09-16 결정).

## 내릴 때

```bash
terraform destroy
```

RDS 는 최종 스냅샷 없이 삭제된다(`skip_final_snapshot`). 탄력적 IP 는 연결만 해제되고 남는다.
