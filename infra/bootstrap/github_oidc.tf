# Lets GitHub Actions exchange its signed OIDC token for short-lived AWS credentials,
# so no AWS access keys are ever stored in GitHub.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  repo = "${var.github_owner}/${var.app_repository}"

  # Which GitHub token subjects ("sub" claims) may assume each role.
  github_subjects = {
    # Only workflows running on main may push images.
    ecr-push = ["repo:${local.repo}:ref:refs/heads/main"]
    # Pull requests may run terraform plan, which only reads.
    terraform-plan = ["repo:${local.repo}:pull_request"]
    # Only jobs in the "dev-teardown" GitHub environment may tear down the dev environment.
    env-destroy = ["repo:${local.repo}:environment:dev-teardown"]
  }
}

# Trust policy shared by the CI roles: the token must come from GitHub, be meant for AWS,
# and carry a subject ("sub") matching the allowed repository and branch or event.
data "aws_iam_policy_document" "github_trust" {
  for_each = local.github_subjects

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# --- Role 1: push images to ECR from main ---

resource "aws_iam_role" "ecr_push" {
  name                 = "${var.project}-github-ecr-push"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["ecr-push"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "Login"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # This action can't be scoped to a repository.
  }

  statement {
    sid = "PushToProjectRepositories"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for repo in aws_ecr_repository.service : repo.arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# --- Role 2: terraform plan on pull requests (read-only) ---

resource "aws_iam_role" "terraform_plan" {
  name                 = "${var.project}-github-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["terraform-plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "terraform_plan_read_only" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plan reads state and writes a short-lived lock file next to it, so it needs these on top of ReadOnlyAccess.
data "aws_iam_policy_document" "terraform_plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "ManageLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "terraform_plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_plan_state.json
}

# --- Role 3: nightly teardown of the dev environment ---
# The cost brake: a scheduled workflow runs `terraform destroy` on infra/envs/dev so a forgotten
# cluster can't run all month. Destroying EKS touches many services, so this role is broad, and the
# trust policy is what keeps it safe: only a job in the dev-teardown environment can assume it.

resource "aws_iam_role" "env_destroy" {
  name                 = "${var.project}-github-env-destroy"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["env-destroy"].json
  max_session_duration = 3600
}

# Covers EC2, VPC, EKS, KMS and CloudWatch Logs, but no IAM.
resource "aws_iam_role_policy_attachment" "env_destroy_power_user" {
  role       = aws_iam_role.env_destroy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "env_destroy" {
  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # The environment's IAM roles and policies carry the project tag (provider default_tags),
  # so the role can only delete IAM resources that belong to this project.
  statement {
    sid = "DeleteProjectIam"
    actions = [
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteOpenIDConnectProvider",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/project"
      values   = [var.project]
    }
  }

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadWriteEnvState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/envs/*"]
  }
}

resource "aws_iam_role_policy" "env_destroy" {
  name   = "env-destroy"
  role   = aws_iam_role.env_destroy.id
  policy = data.aws_iam_policy_document.env_destroy.json
}
