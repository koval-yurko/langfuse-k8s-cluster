output "rds_endpoint" {
  description = "Endpoint of the RDS PostgreSQL instance"
  value       = module.rds.db_instance_endpoint
}

output "rds_password" {
  description = "Password for the RDS PostgreSQL instance"
  value       = random_password.db.result
  sensitive   = true
}
