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

resource "aws_security_group" "backend" {
  name        = "cjj-backend"
  description = "backend api: 8000 public (DEMO_API_KEY guarded), ssh from my ip"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "api"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
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
