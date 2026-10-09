# 0004: Two Terraform layers, with state in S3

**Status:** accepted, 2026-10-08

## Context
The environment must be cheap: an EKS cluster left running costs about $220 a month, so it has to be destroyed after each working session. Some things must survive that, though: Terraform state, container images, the CI roles, and cost alerts.

## Decision
- **Bootstrap layer** (`infra/bootstrap`): permanent, under $1 a month. State bucket, ECR, GitHub OIDC and CI roles, budgets.
- **Environment layer** (`infra/envs/dev`, Phase 2): VPC, EKS, RDS, SQS. Created and destroyed freely.
- State for both lives in one versioned S3 bucket with **S3-native locking** (`use_lockfile = true`, Terraform 1.10+), so no DynamoDB lock table is needed.
- The bootstrap layer starts with local state and migrates into the bucket it creates.

## Consequences
- `terraform destroy` on the environment never touches images, roles or state.
- One bucket per account keeps things simple. A team setup would usually separate state per account or environment.
- The bucket name contains the account ID, so backend settings live in an uncommitted `backend.hcl`.
