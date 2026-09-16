#!/usr/bin/env bash
# 작업 없는 날 EC2·RDS 를 중지한다. EIP 는 연결된 채 남고(중지 인스턴스에 붙은 EIP 는 시간당 과금),
# RDS 중지는 7일 뒤 자동 재시작된다. 사용: bash tools/infra/pause.sh
set -euo pipefail
[ -d /opt/homebrew/opt/expat/lib ] && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/expat/lib:${DYLD_LIBRARY_PATH:-}"
REGION=ap-northeast-2
INFRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../infra" && pwd)"
IID=$(terraform -chdir="$INFRA" output -raw backend_instance_id)
aws ec2 stop-instances --region "$REGION" --instance-ids "$IID" --query 'StoppingInstances[].CurrentState.Name' --output text
aws rds stop-db-instance --region "$REGION" --db-instance-identifier cjj-postgres --query 'DBInstance.DBInstanceStatus' --output text
