output "state_bucket" {
  description = "S3 bucket holding Terraform state for every layer."
  value       = aws_s3_bucket.state.bucket
}

output "backend_config" {
  description = "Contents for backend.hcl, used when migrating this layer's state into S3."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "bootstrap/terraform.tfstate"
    region       = "${var.region}"
    use_lockfile = true
    encrypt      = true
  EOT
}

output "ecr_repository_urls" {
  description = "Image repository URL for each service."
  value       = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

output "github_ecr_push_role_arn" {
  description = "Role GitHub Actions assumes on main to push images."
  value       = aws_iam_role.ecr_push.arn
}

output "github_terraform_plan_role_arn" {
  description = "Role GitHub Actions assumes on pull requests to run terraform plan."
  value       = aws_iam_role.terraform_plan.arn
}

output "github_role_subjects" {
  description = "GitHub token subjects each CI role trusts."
  value       = local.github_subjects
}
