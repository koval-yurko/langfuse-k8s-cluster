resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "langfuse" {
  bucket        = "langfuse-dev-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "langfuse" {
  bucket = aws_s3_bucket.langfuse.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
