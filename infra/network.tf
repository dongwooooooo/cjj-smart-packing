data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 인스턴스 유형이 제공되는 AZ 의 서브넷만 고른다 (c7i-flex.large 는 ap-northeast-2a 에서 거부됨, 2026-09-16).
data "aws_ec2_instance_type_offerings" "backend" {
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
  location_type = "availability-zone"
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  backend_subnet_id = [
    for s in data.aws_subnet.default : s.id
    if contains(data.aws_ec2_instance_type_offerings.backend.locations, s.availability_zone)
  ][0]
}

# 인라인 ingress/egress 블록과 aws_security_group_rule 을 섞으면 apply 때마다 인라인 쪽이 독립 규칙을 지운다
# (2026-09-22 실측: 모니터링 포트 규칙이 다음 apply 에서 사라짐). 그래서 이 SG 의 규칙은 전부 독립 리소스로 둔다.
resource "aws_security_group" "backend" {
  name        = "cjj-backend"
  description = "backend api: 8000 public (DEMO_API_KEY guarded), ssh from my ip"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "backend_api_public" {
  type              = "ingress"
  security_group_id = aws_security_group.backend.id
  from_port         = 8000
  to_port           = 8000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "api"
}

resource "aws_security_group_rule" "backend_ssh_me" {
  type              = "ingress"
  security_group_id = aws_security_group.backend.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${var.my_ip}/32"]
  description       = "ssh from my ip"
}

resource "aws_security_group_rule" "backend_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.backend.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "rds" {
  name        = "cjj-rds"
  description = "postgres from backend sg only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 기본 VPC 의 서브넷 4개가 IGW 경로 없는 라우트 테이블에 명시 연결돼 있었다(2026-09-16 확인).
# 인스턴스가 밖으로도 안으로도 통하지 않아 docker 설치·SSM 등록·SSH 가 전부 막혔다. 기본 경로를 추가한다.
data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_route_table" "backend_subnet" {
  subnet_id = local.backend_subnet_id
}

resource "aws_route" "backend_subnet_igw" {
  route_table_id         = data.aws_route_table.backend_subnet.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.default.id
}
