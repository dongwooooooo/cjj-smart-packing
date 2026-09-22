# 부하 테스트용 자원. 모니터링(Prometheus·Grafana)은 백엔드 인스턴스의 별도 compose 프로젝트로 뜨고,
# 부하 발생기(k6)는 같은 VPC 의 별도 인스턴스에서 돌린다. 노트북에서 쏘면 인터넷 왕복이 지연에 섞인다.

# Grafana(3000)·Prometheus(9090)는 내 IP 에서만 본다.
resource "aws_security_group_rule" "monitoring_from_me" {
  for_each          = { grafana = 3000, prometheus = 9090 }
  type              = "ingress"
  security_group_id = aws_security_group.backend.id
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = ["${var.my_ip}/32"]
  description       = "${each.key} from my ip"
}

resource "aws_security_group" "loadgen" {
  count       = var.loadgen_enabled ? 1 : 0
  name        = "cjj-loadgen"
  description = "k6 load generator: ssh from my ip"
  vpc_id      = data.aws_vpc.default.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 부하 발생기는 백엔드 API(8000)와 Prometheus remote write(9090)에 접근한다.
resource "aws_security_group_rule" "backend_from_loadgen" {
  for_each                 = var.loadgen_enabled ? { api = 8000, prometheus = 9090 } : {}
  type                     = "ingress"
  security_group_id        = aws_security_group.backend.id
  from_port                = each.value
  to_port                  = each.value
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.loadgen[0].id
  description              = "${each.key} from loadgen"
}

resource "aws_instance" "loadgen" {
  count                       = var.loadgen_enabled ? 1 : 0
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.loadgen_instance_type
  subnet_id                   = local.backend_subnet_id
  vpc_security_group_ids      = [aws_security_group.loadgen[0].id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = <<-EOT
    #!/bin/bash
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" > /etc/apt/sources.list.d/k6.list
    apt-get update -y && apt-get install -y k6 jq
  EOT
  root_block_device {
    volume_size = 16
    volume_type = "gp3"
  }
  tags = { Name = "cjj-loadgen" }
  lifecycle {
    ignore_changes = [ami]
  }
  depends_on = [aws_route.backend_subnet_igw]
}

output "loadgen_public_ip" {
  value = var.loadgen_enabled ? aws_instance.loadgen[0].public_ip : null
}

output "backend_private_ip" {
  value = aws_instance.backend.private_ip
}
