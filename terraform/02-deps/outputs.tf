output "rds_endpoint" {
  description = "Endpoint of the RDS PostgreSQL instance"
  value       = module.rds.db_instance_endpoint
}

output "rds_password" {
  description = "Password for the RDS PostgreSQL instance"
  value       = random_password.db.result
  sensitive   = true
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Langfuse storage"
  value       = aws_s3_bucket.langfuse.id
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket for Langfuse storage"
  value       = aws_s3_bucket.langfuse.region
}
