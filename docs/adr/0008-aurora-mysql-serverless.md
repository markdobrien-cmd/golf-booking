# 0008: Aurora MySQL Serverless v2 as a learning side-build

**Status:** accepted, 2026-11-06

## Context
The golf services use PostgreSQL (ADR 0002). Mark wants hands-on experience with Aurora MySQL too,
because it comes up in DevOps interviews. It should cost close to nothing and follow the same
rules as the rest of the dev environment.

## Decision
Add one Aurora MySQL cluster to `infra/envs/dev` (`aurora_mysql.tf`):

- **Serverless v2** (`db.serverless` instance, 0 to 2 ACUs). With a minimum of 0 the instance
  pauses after 5 idle minutes, so an idle database costs only storage.
- **Private subnets only**, reached on 3306 only from the EKS node security group.
- **Password managed by RDS in Secrets Manager** (`manage_master_user_password`), so it is never
  in code, tfvars or Terraform state.
- **Encrypted storage**, one day of backups, no final snapshot and no deletion protection, so the
  nightly teardown (ADR 0006) can remove it.

### Alternatives considered
- **Provisioned instances (e.g. db.t4g.medium):** a fixed hourly cost even when idle.
- **The community `terraform-aws-modules/rds-aurora` module:** less code, but hides the four
  building blocks this exercise is meant to show. Worth switching to once they're familiar.
- **A separate Terraform root:** cleaner isolation, but it would need its own VPC or a remote-state
  lookup, and wouldn't be covered by the nightly teardown.

## Consequences
- The first query after a pause waits about 15 seconds while the instance resumes.
- It shares the dev lifecycle: destroyed nightly, data is not kept.
- For production you'd flip the dev settings: deletion protection on, final snapshot, longer
  backups, a minimum capacity above 0, and a reader instance in a second AZ for failover.
