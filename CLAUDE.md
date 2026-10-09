# Working on golf-booking

This repo is a learning project: Mark is building it to learn Terraform, EKS/Helm and
GitHub Actions + Argo CD for DevOps interviews. Help him understand, not just finish.

## How to help
- Explain what a change does and why before making it. Relate it to Ansible or Jenkins where that helps.
- When Mark asks to write something himself, give hints and review his attempt instead of writing it for him.
- Keep changes small and on a feature branch; `main` only changes through pull requests.

## Safety
- Never run `terraform apply`, `terraform destroy`, or anything else that changes AWS. Mark runs those himself.
  `terraform fmt`, `validate`, `plan` and `test` are fine.
- AWS access is via the SSO profile `golf` (`export AWS_PROFILE=golf`, `aws sso login`). Never write credentials to files.
- Never commit `terraform.tfvars`, `backend.hcl`, state files or account-specific values.

## Layout
- `services/`: four Python/FastAPI services; `make test` and `make lint` run their checks, `make up` runs them locally with Docker Compose.
- `infra/bootstrap/`: permanent Terraform layer (state bucket, ECR, GitHub OIDC roles, budget). State lives in S3.
- `docs/adr/`: decision records. Add one for each significant design choice.
