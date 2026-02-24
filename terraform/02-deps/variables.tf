variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name"
  type        = string
}
