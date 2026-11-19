terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
    # Installs Helm charts into the EKS cluster, the way `helm install` would.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    # Generates passwords (Grafana admin, MySQL exporter user) so none are written in code.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # State for this environment lives in the bootstrap bucket under its own key.
  # The bucket name is account-specific, so it's passed at init time (see README.md).
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project     = var.project
      environment = var.environment
      layer       = "env"
      managed-by  = "terraform"
    }
  }
}

# Helm talks to the Kubernetes API. It gets a short-lived token from `aws eks get-token` using
# whatever AWS login runs Terraform (your SSO profile, or the teardown role in GitHub Actions).
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
