# 0009: Prometheus and Grafana on EKS, installed by Terraform

**Status:** accepted, 2026-11-19

## Context
We need to see what the Aurora MySQL cluster (ADR 0008) and EKS are doing, in one place, at
better than CloudWatch's 1 to 5 minute resolution, and with alerts. This is also the monitoring
the golf services will use: they already expose Prometheus metrics on `/metrics`.

## Decision
Install `kube-prometheus-stack`, the YACE CloudWatch exporter and `mysqld_exporter` as
`helm_release` resources in `infra/envs/dev/monitoring.tf`.

- **Two views of the database.** YACE reads AWS's CloudWatch metrics (ACUs, latency, replica
  lag), which only AWS can see. mysqld_exporter reads MySQL's own counters (buffer pool, temp
  tables, lock waits), which CloudWatch doesn't have.
- **Pod Identity for AWS access.** YACE's service account maps to a read-only IAM role, so there
  are no access keys in the cluster.
- **Generated passwords.** Grafana's admin password and the exporter's MySQL password come from
  `random_password`. They are in Terraform state (encrypted S3), never in code.
- **No persistence.** Prometheus keeps 2 days in memory-backed storage. The cluster is destroyed
  nightly, so persistent volumes would add cost and a storage driver for nothing.
- **The teardown role gets an EKS access entry**, so `terraform destroy` in GitHub Actions can
  remove the Helm releases through the Kubernetes API.

### Alternatives considered
- **Amazon Managed Prometheus + Managed Grafana:** no servers to run and long retention, but
  more setup and a monthly cost floor. That's the production choice for a team.
- **CloudWatch dashboards only:** simplest, but no MySQL internals and nothing reusable for the
  services' own metrics.
- **Installing the charts with Argo CD:** that's where apps will go (Phase 6). Cluster add-ons
  that need IAM roles and Terraform-generated values sit better in Terraform for now.

## Consequences
- mysqld_exporter stops Aurora auto-pausing while it runs (`enable_mysql_exporter` turns it off).
- Metrics are lost at each nightly teardown. Acceptable for dev.
- The teardown role is now a Kubernetes cluster admin as well. It already has PowerUserAccess,
  so this doesn't widen what it could break.
