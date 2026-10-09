terraform {
  # 1.10+ is needed for S3-native state locking (use_lockfile), which removes the DynamoDB lock table.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags, so Cost Explorer can show what the project costs.
  default_tags {
    tags = {
      project    = var.project
      layer      = "bootstrap"
      managed-by = "terraform"
    }
  }
}
