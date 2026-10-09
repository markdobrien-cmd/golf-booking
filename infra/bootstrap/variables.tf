variable "region" {
  description = "AWS region for everything in the project."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Name used as a prefix and in tags."
  type        = string
  default     = "golf-booking"
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repositories."
  type        = string
  default     = "markdobrien-cmd"
}

variable "app_repository" {
  description = "Repository whose GitHub Actions workflows may assume the CI roles."
  type        = string
  default     = "golf-booking"
}

variable "services" {
  description = "One ECR repository is created per service image."
  type        = set(string)
  default     = ["web", "courses-api", "bookings-api", "notifications-worker"]
}

variable "budget_email" {
  description = "Where AWS Budgets sends cost alerts. Set it in terraform.tfvars, which is not committed."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly spend that triggers alerts. Alerts fire at 50% and 100% of actual spend, and when the forecast passes 100%."
  type        = number
  default     = 30
}
