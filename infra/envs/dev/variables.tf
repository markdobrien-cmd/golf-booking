variable "region" {
  description = "AWS region for the environment."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "golf-booking"
}

variable "environment" {
  description = "Environment name, used in resource names and tags."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Check what's supported with: aws eks describe-cluster-versions --region eu-west-1"
  type        = string
  default     = "1.35"
}

variable "api_allowed_cidrs" {
  description = "Address ranges allowed to reach the cluster API. Every request still needs a valid AWS login; narrow this to your own IP (x.x.x.x/32) for extra safety."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mysql_engine_version" {
  description = "Aurora MySQL version. Scaling to 0 ACUs needs 3.08 or later. List versions with: aws rds describe-db-engine-versions --engine aurora-mysql --query 'DBEngineVersions[].EngineVersion'"
  type        = string
  default     = "8.0.mysql_aurora.3.10.0"
}
