resource "aws_iam_policy" "langfuse_s3" {
  name        = "langfuse-dev-s3-access"
  description = "S3 access for Langfuse pods via IRSA"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.langfuse.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.langfuse.arn
      }
    ]
  })
}

module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4"

  name = "langfuse-dev-s3-irsa"

  oidc_providers = {
    main = {
      provider_arn               = data.tfe_outputs.network.values.oidc_provider_arn
      namespace_service_accounts = ["langfuse:langfuse-web"]
    }
  }

  policies = {
    langfuse_s3 = aws_iam_policy.langfuse_s3.arn
  }
}
