output "backend_public_ip" {
  value = var.existing_eip == null ? aws_instance.backend.public_ip : var.existing_eip
}

output "backend_instance_id" {
  value = aws_instance.backend.id
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.repos : k => r.repository_url }
}

output "images_bucket" {
  value = aws_s3_bucket.images.bucket
}

output "eval_bucket" {
  value = aws_s3_bucket.eval.bucket
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "inference_api_key" {
  value     = random_password.inference_api_key.result
  sensitive = true
}

output "demo_api_key" {
  description = "Vercel 프론트의 서버 사이드 환경변수로 넣는 값 (X-Demo-Key)."
  value       = random_password.demo_api_key.result
  sensitive   = true
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "github_setup" {
  description = "두 공개 저장소에 등록할 Actions 시크릿·변수"
  value       = <<-EOT
    gh secret set AWS_ROLE_ARN --repo ${var.github_owner}/cjj-smart-packing-backend --body '${aws_iam_role.github_actions.arn}'
    gh secret set AWS_ROLE_ARN --repo ${var.github_owner}/cjj-smart-packing-ai      --body '${aws_iam_role.github_actions.arn}'
    gh variable set EC2_INSTANCE_ID --repo ${var.github_owner}/cjj-smart-packing-backend --body '${aws_instance.backend.id}'
    gh secret set HF_TOKEN --repo ${var.github_owner}/cjj-smart-packing-ai --body '<read 전용 토큰>'
  EOT
}
