# 이미지가 ECR 에 있어야 함수를 만들 수 있다. 1차 apply 뒤 이미지를 push 하고 lambda_enabled=true 로 2차 apply.
resource "aws_lambda_function" "dimension" {
  count         = var.lambda_enabled ? 1 : 0
  function_name = local.lambda_name
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.repos[local.lambda_ecr].repository_url}:${var.lambda_image_tag}"
  role          = aws_iam_role.lambda_exec.arn
  architectures = ["x86_64"]
  memory_size   = var.lambda_memory_mb
  timeout       = 60
  publish       = true

  environment {
    variables = {
      API_KEY   = random_password.inference_api_key.result
      N_THREADS = tostring(var.lambda_threads)
    }
  }

  # 코드 갱신은 CI(build-deploy)가 한다. terraform 은 설정만 관리한다.
  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

# 백엔드는 항상 :live 를 호출한다. 어느 버전을 가리킬지는 CI 가 옮긴다.
resource "aws_lambda_alias" "live" {
  count            = var.lambda_enabled ? 1 : 0
  name             = "live"
  function_name    = aws_lambda_function.dimension[0].function_name
  function_version = aws_lambda_function.dimension[0].version

  lifecycle {
    ignore_changes = [function_version]
  }
}
