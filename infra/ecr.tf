# 저장소 이름은 두 공개 저장소의 워크플로(env.ECR_REPO)가 기대하는 값 그대로다.
resource "aws_ecr_repository" "repos" {
  for_each             = toset([local.backend_ecr, local.lambda_ecr])
  name                 = each.key
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "keep_recent" {
  for_each   = aws_ecr_repository.repos
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
