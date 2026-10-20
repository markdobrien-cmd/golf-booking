# 0006: Nightly teardown as the cost brake

**Status:** accepted, 2026-10-13

## Context
AWS has no hard spending cap. The dev environment costs roughly $0.30 an hour while up, about $220
a month if forgotten. Budget emails (ADR 0004) warn, but only after money is spent, and only if
someone reads them.

## Decision
A scheduled GitHub Actions workflow (`.github/workflows/nightly-teardown.yml`) runs
`terraform destroy` on `infra/envs/dev` at 22:00 UTC every night, and can be run by hand.

- It logs in to AWS with OIDC through a dedicated role, `golf-booking-github-env-destroy`, which
  trusts only jobs running in the `dev-teardown` GitHub environment of this repository.
- The role has PowerUserAccess plus permission to delete IAM resources tagged
  `project = golf-booking`, and read/write access to the `envs/` state only.
- It skips cleanly when nothing is running, so a quiet night costs nothing and sends no failure.

### Alternatives considered
- **Manual destroy plus budget alerts:** relies on remembering, which is what failed in the first place.
- **A Lambda function that deletes the cluster:** acts outside Terraform, leaving its state out of
  sync and needing manual clean-up afterwards.
- **An AWS Budgets action that denies new resources:** stops new spending but doesn't remove a
  running cluster, and it would have to attach policies to IAM Identity Center roles.

## Consequences
- The role can do almost anything outside IAM. That's acceptable for a personal demo account; a team
  would scope it per service or run teardown from a separate tooling account.
- Work left running overnight is lost, by design. The environment rebuilds from code in about 15 minutes.
