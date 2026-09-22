variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "my_ip" {
  description = "SSH 허용 IP (CIDR 없이). curl https://checkip.amazonaws.com"
  type        = string
}

variable "key_name" {
  description = "EC2 키페어 이름. SSH 는 비상용이고 배포는 SSM 으로 한다."
  type        = string
  default     = "key"
}

variable "instance_type" {
  description = "백엔드 EC2 유형. 프리티어 플랜은 허용 유형이 제한된다 (c7i-flex.large 확인됨, c7i.xlarge 거부됨)."
  type        = string
  default     = "c7i-flex.large"
}

variable "existing_eip" {
  description = "재사용할 기존 탄력적 IP. 없으면 null (새로 만들지 않고 인스턴스 공인 IP 사용)."
  type        = string
  default     = "13.124.19.3"
  nullable    = true
}

variable "github_owner" {
  type    = string
  default = "dongwooooooo"
}

variable "github_owner_id" {
  description = "gh api users/<owner> --jq .id"
  type        = number
  default     = 137749703
}

variable "github_repos" {
  description = "OIDC 역할을 쓸 저장소 이름과 ID. gh api repos/<owner>/<repo> --jq .id"
  type        = map(number)
  default = {
    "cjj-smart-packing-backend" = 1372630340
    "cjj-smart-packing-ai"      = 1372630494
  }
}

variable "rds_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "rds_engine_version" {
  description = "PostgreSQL 메이저 버전. 팀 구성은 postgres:18 (D-16)."
  type        = string
  default     = "18"
}

variable "lambda_enabled" {
  description = "ECR 에 추론 이미지를 올린 뒤 true 로 바꿔 함수를 만든다."
  type        = bool
  default     = false
}

variable "lambda_image_tag" {
  type    = string
  default = "latest"
}

variable "lambda_memory_mb" {
  description = "계정 쿼터가 3,008MB 였다 (2026-08 확인). 10,240 은 Support 케이스 필요."
  type        = number
  default     = 3008
}

variable "lambda_threads" {
  description = "ONNX Runtime intra_op 스레드. 3,008MB 에서 배정 vCPU 는 약 2."
  type        = number
  default     = 2
}

variable "inference_timeout_seconds" {
  type    = number
  default = 8
}

variable "backend_image_tag" {
  type    = string
  default = "latest"
}

variable "loadgen_enabled" {
  description = "부하 발생기 EC2(k6) 생성 여부. 부하 테스트 기간에만 true."
  type        = bool
  default     = false
}

variable "loadgen_instance_type" {
  type    = string
  default = "c7i-flex.large"
}
