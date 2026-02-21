terraform {
  required_version = ">= 1.11.1"

  cloud {
    workspaces {
      name = "langfuse-app"
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.tfe_outputs.network.values.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.tfe_outputs.network.values.cluster_endpoint
    cluster_ca_certificate = base64decode(data.tfe_outputs.network.values.cluster_ca_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubernetes" {
  host                   = data.tfe_outputs.network.values.cluster_endpoint
  cluster_ca_certificate = base64decode(data.tfe_outputs.network.values.cluster_ca_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}
