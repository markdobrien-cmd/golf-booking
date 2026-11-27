terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }

  # Own state key in the bootstrap bucket, so this lab is created and destroyed independently of dev.
  # The bucket name is account-specific, so it's passed at init time (see README.md).
  backend "s3" {
    key          = "envs/monlab/terraform.tfstate"
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
