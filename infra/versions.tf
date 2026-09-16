terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "cjj-smart-packing", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  account_id    = data.aws_caller_identity.me.account_id
  lambda_name   = "logistics-dimension-api"
  lambda_arn    = "arn:aws:lambda:${var.region}:${local.account_id}:function:${local.lambda_name}"
  backend_ecr   = "cj-ai-backend"
  lambda_ecr    = "logistics-dimension-api"
  images_bucket = "cjj-images-${local.account_id}"
  eval_bucket   = "cjj-eval-data-${local.account_id}"
}
