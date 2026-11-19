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

variable "app_image_tag" {
  description = "Git commit SHA of the images to run (CI tags each image with its commit). List them with: aws ecr describe-images --repository-name golf-booking/web --query 'imageDetails[].imageTags' --output text"
  type        = string
  default     = "ec3ed242f27631af1945272b2c9dc48db426b2e2" # main after PR #13, the first images CI published
}
