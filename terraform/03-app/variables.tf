variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name for cross-workspace data access"
  type        = string
}

variable "langfuse_admin_email" {
  description = "Email address for the initial Langfuse admin user"
  type        = string
}

variable "langfuse_admin_name" {
  description = "Display name for the initial Langfuse admin user"
  type        = string
}

variable "langfuse_admin_password" {
  description = "Password for the initial Langfuse admin user"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.langfuse_admin_password) >= 8
    error_message = "Password must be at least 8 characters."
  }
}
