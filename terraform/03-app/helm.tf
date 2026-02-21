resource "helm_release" "langfuse" {
  name             = "langfuse"
  repository       = "https://langfuse.github.io/langfuse-k8s"
  chart            = "langfuse"
  version          = "~> 1.5"
  namespace        = "langfuse"
  create_namespace = true

  # Extra headroom for ClickHouse/Redis cold-start on slow EBS provisioning
  timeout = 600

  values = [templatefile("${path.module}/values.yaml.tpl", {
    rds_host        = split(":", data.tfe_outputs.deps.values.rds_endpoint)[0]
    rds_password    = data.tfe_outputs.deps.values.rds_password
    s3_bucket       = data.tfe_outputs.deps.values.s3_bucket_name
    s3_region       = data.tfe_outputs.deps.values.s3_bucket_region
    irsa_role_arn   = data.tfe_outputs.deps.values.irsa_role_arn
    nextauth_secret = random_password.nextauth_secret.result
    salt            = random_password.salt.result
    encryption_key  = random_id.encryption_key.hex
    admin_email     = var.langfuse_admin_email
    admin_name      = var.langfuse_admin_name
    admin_password  = var.langfuse_admin_password
  })]
}
