# 평가용 x86 EC2 1대 — VS 이미지 rclone 복사 + FP32/FP16/INT8 PTQ 평가 + 속도 실측.
# 쓰고 나면 terraform destroy. SSH 는 my_ip 에서만.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = "ap-northeast-2"
}

variable "my_ip" {
  type = string
}
variable "key_name" {
  type    = string
  default = "key"
}
variable "instance_type" {
  type    = string
  default = "c7i.xlarge"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}
data "aws_vpc" "default" { default = true }

resource "aws_security_group" "eval" {
  name        = "cjj-eval-ssh"
  description = "cjj eval box: ssh from my ip only"
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
  tags = { Project = "cjj-eval" }
}

resource "aws_instance" "eval" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.eval.id]
  root_block_device {
    volume_size = 60
    volume_type = "gp3"
  }
  user_data = <<-EOT
    #!/bin/bash
    set -e
    apt-get update -y && apt-get install -y python3-venv python3-pip unzip jq
    curl -fsSL https://rclone.org/install.sh | bash
    mkdir -p /home/ubuntu/eval && chown ubuntu:ubuntu /home/ubuntu/eval
    touch /home/ubuntu/READY && chown ubuntu:ubuntu /home/ubuntu/READY
  EOT
  tags      = { Name = "cjj-eval", Project = "cjj-eval" }
}

output "public_ip" {
  value = aws_instance.eval.public_ip
}
output "ami" {
  value = data.aws_ami.ubuntu.id
}
