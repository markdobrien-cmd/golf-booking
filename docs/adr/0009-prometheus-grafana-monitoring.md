# 0009: Prometheus and Grafana for the app, and the app on EKS via a Helm chart

**Status:** accepted, 2026-11-19

## Context
The four services already expose Prometheus metrics (`/metrics`: request counts by route and
status, latency histograms, worker throughput). Nothing collects them yet, and the services
don't run on EKS yet. We want dashboards and alerts that answer "is booking working?" for
customers, not only "are the nodes busy?".

## Decision
- **kube-prometheus-stack** (`infra/envs/dev/monitoring.tf`): Prometheus, Grafana, Alertmanager,
  node-exporter and kube-state-metrics in the `monitoring` namespace. Prometheus picks up
  ServiceMonitors and rules from every namespace.
- **One Helm chart for the app** (`charts/golf-booking`): every entry under `services` becomes a
  Deployment and Service. Dev stand-ins for Postgres and SQS (the Docker Compose images) and a
  load generator are switchable with values.
- **The app owns its monitoring.** The chart ships its ServiceMonitor, alert rules and Grafana
  dashboard, so they're versioned and reviewed with the code they describe.
- **Alerts on symptoms:** error rate, latency, stalled notifications, crash loops. These are
  what customers feel; CPU is on the dashboard, not paging anyone.
- **Installed by Terraform for now** (`infra/envs/dev/app.tf`), so one `apply` brings dev up.
- **The teardown role gets an EKS access entry**, so `terraform destroy` in GitHub Actions can
  remove the Helm releases through the Kubernetes API.

### Alternatives considered
- **Amazon Managed Prometheus and Managed Grafana:** no servers to run and long retention, but
  more setup and a monthly cost floor. The production choice for a team.
- **CloudWatch Container Insights:** quick, but doesn't read the services' own metrics without
  extra agents, and the dashboards aren't portable.
- **Argo CD for the app now:** the end state (Phase 6). Terraform is the stop-gap until then.

## Consequences
- No persistent storage: metrics and dev data are lost at each nightly teardown.
- The app's version is a Terraform variable until Argo CD takes over.
- Writing the error dashboard exposed a bug: unhandled exceptions weren't counted, so a crash
  showed as 0% errors. `metrics.py` now records them as 500s, with a test.
- The teardown role is now a Kubernetes cluster admin as well. It already has PowerUserAccess,
  so this doesn't widen what it could break.
