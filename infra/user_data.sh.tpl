#!/bin/bash
# 첫 부팅: docker 설치, 배포 경로와 .env 준비. 코드는 GitHub Actions(deploy-ec2)가 SSM 으로 배치한다.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ubuntu

# 배포 워크플로는 ~/backend 가 git 저장소가 아니면 백업 후 clone 하고 백업의 .env 를 옮긴다.
install -d -o ubuntu -g ubuntu -m 0755 /home/ubuntu/backend
cat > /home/ubuntu/backend/.env <<'ENVEOF'
${env_lines}
ENVEOF
chown ubuntu:ubuntu /home/ubuntu/backend/.env
chmod 0600 /home/ubuntu/backend/.env

# SSM 에이전트는 Ubuntu AMI 에 snap 으로 들어 있다. 상태만 확인한다.
snap list amazon-ssm-agent >/dev/null 2>&1 || snap install amazon-ssm-agent --classic
systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service || true
