# 촬영 사진·시연 상품 사진 (STORAGE_BUCKET). 조회는 30분 presigned URL.
resource "aws_s3_bucket" "images" {
  bucket        = local.images_bucket
  force_destroy = true
}

# 고정셋 평가 데이터 (VS 2,024품목 × 3장). 게이트가 파이프라인에서 읽는다. 비공개.
resource "aws_s3_bucket" "eval" {
  bucket        = local.eval_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each                = { images = aws_s3_bucket.images.id, eval = aws_s3_bucket.eval.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "all" {
  for_each = { images = aws_s3_bucket.images.id, eval = aws_s3_bucket.eval.id }
  bucket   = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
