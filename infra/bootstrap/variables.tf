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

# GitHub's numeric IDs for the owner and the repository. Newer repositories put them in the OIDC
# "sub" claim ("immutable subject"), so a deleted repository re-created under the same name can't
# inherit the roles. They are public: `gh api repos/OWNER/REPO --jq '.owner.id, .id'`.
variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner."
  type        = number
  default     = 339532401
}

variable "app_repository_id" {
  description = "Numeric ID of the app repository."
  type        = number
  default     = 1410036578
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
