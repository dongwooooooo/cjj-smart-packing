#!/usr/bin/env bash
# 중지한 EC2·RDS 를 다시 켠다. 백엔드 컨테이너는 restart: unless-stopped 라 인스턴스가 뜨면 따라 뜬다.
# RDS 가 available 이 될 때까지 기다린 뒤 헬스를 확인한다. 사용: bash tools/infra/resume.sh
set -euo pipefail
[ -d /opt/homebrew/opt/expat/lib ] && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/expat/lib:${DYLD_LIBRARY_PATH:-}"
REGION=ap-northeast-2
INFRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../infra" && pwd)"
IID=$(terraform -chdir="$INFRA" output -raw backend_instance_id)
IP=$(terraform -chdir="$INFRA" output -raw backend_public_ip)
aws rds start-db-instance --region "$REGION" --db-instance-identifier cjj-postgres --query 'DBInstance.DBInstanceStatus' --output text || true
aws ec2 start-instances --region "$REGION" --instance-ids "$IID" --query 'StartingInstances[].CurrentState.Name' --output text
echo "RDS available 대기..."
aws rds wait db-instance-available --region "$REGION" --db-instance-identifier cjj-postgres
echo "백엔드 헬스 대기 (최대 5분)..."
for _ in $(seq 1 30); do
  if curl -s -m 5 "http://${IP}:8000/actuator/health" | grep -q '"UP"'; then echo "UP http://${IP}:8000"; exit 0; fi
  sleep 10
done
echo "헬스 실패 — 인스턴스에서 docker compose ps 확인" >&2; exit 1
