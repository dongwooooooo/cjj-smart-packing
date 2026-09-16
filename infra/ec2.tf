data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# 백엔드 → Lambda X-API-Key, 화면 → 백엔드 X-Demo-Key
resource "random_password" "inference_api_key" {
  length  = 40
  special = false
}

resource "random_password" "demo_api_key" {
  length  = 40
  special = false
}

locals {
  backend_env = {
    COMPOSE_FILE              = "docker-compose.yml"
    BACKEND_IMAGE             = "${aws_ecr_repository.repos[local.backend_ecr].repository_url}:${var.backend_image_tag}"
    POSTGRES_HOST             = aws_db_instance.postgres.address
    POSTGRES_PORT             = "5432"
    POSTGRES_USER             = aws_db_instance.postgres.username
    POSTGRES_PASSWORD         = random_password.db.result
    POSTGRES_DB               = aws_db_instance.postgres.db_name
    INFERENCE_LAMBDA_FUNCTION = "${local.lambda_name}:live"
    INFERENCE_API_KEY         = random_password.inference_api_key.result
    INFERENCE_TIMEOUT_SECONDS = tostring(var.inference_timeout_seconds)
    STORAGE_BUCKET            = aws_s3_bucket.images.bucket
    STORAGE_AWS_REGION        = var.region
    DEMO_API_KEY              = random_password.demo_api_key.result
  }
}

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = local.backend_subnet_id
  vpc_security_group_ids = [aws_security_group.backend.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.backend_ec2.name

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    env_lines = join("\n", [for k, v in local.backend_env : "${k}=${v}"])
  })
  user_data_replace_on_change = false

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # 컨테이너 안의 백엔드가 IMDS 로 인스턴스 프로파일 자격증명을 받으려면 hop limit 2 가 필요하다.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = { Name = "cjj-backend" }

  # 부팅 스크립트가 인터넷 없이 돌면 docker 가 없다. 경로가 먼저 있어야 한다.
  depends_on = [aws_route.backend_subnet_igw]

  lifecycle {
    ignore_changes = [ami]
  }
}

data "aws_eip" "existing" {
  count     = var.existing_eip == null ? 0 : 1
  public_ip = var.existing_eip
}

resource "aws_eip_association" "backend" {
  count         = var.existing_eip == null ? 0 : 1
  instance_id   = aws_instance.backend.id
  allocation_id = data.aws_eip.existing[0].id
}
