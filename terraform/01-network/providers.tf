terraform {
  required_version = ">= 1.6"

  cloud {
    workspaces {
      name = "langfuse-network"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.62"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
