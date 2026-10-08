# Runs offline with `terraform test`: the AWS provider is mocked, so nothing is created
# and no credentials are needed. It checks the rules that matter most if they break.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

variables {
  budget_email = "alerts@example.com"
}

run "state_bucket_is_protected" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "golf-booking-tfstate-123456789012"
    error_message = "State bucket name should include the account ID."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State bucket must be versioned so a bad apply can be undone."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    error_message = "State bucket must block public access."
  }
}

run "one_immutable_ecr_repository_per_service" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository.service) == 4
    error_message = "Expected one ECR repository per service."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.service : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "Image tags must be immutable."
  }
}

run "ci_roles_are_scoped_to_the_repository" {
  command = plan

  assert {
    condition     = output.github_role_subjects["ecr-push"] == ["repo:markdobrien-cmd/golf-booking:ref:refs/heads/main"]
    error_message = "Only main in golf-booking may push images."
  }

  assert {
    condition     = output.github_role_subjects["terraform-plan"] == ["repo:markdobrien-cmd/golf-booking:pull_request"]
    error_message = "The plan role should be limited to pull requests in golf-booking."
  }
}
