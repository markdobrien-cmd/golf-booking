# Dev environment

The destroyable layer: the network (your module), the EKS cluster, Prometheus and Grafana, and the
golf booking app itself ([ADR 0009](../../../docs/adr/0009-prometheus-grafana-monitoring.md)).
Aurora PostgreSQL and SQS come next; until then the app uses in-cluster stand-ins.
See [ADR 0005](../../../docs/adr/0005-eks-and-network-layout.md) for the reasoning.

> **Cost:** about $0.25 an hour while it's up (EKS control plane, NAT gateway, three small nodes).
> The [nightly teardown](../../../.github/workflows/nightly-teardown.yml) destroys it at 22:00 UTC
> if you forget.

## Exercise: call the network module

`main.tf` has an empty "Network" section. The EKS block already uses `module.network.vpc_id` and
`module.network.private_subnet_ids`, so `terraform validate` fails until you add the module call.

Check your work offline (no AWS login needed):

```bash
cd infra/envs/dev
terraform init -backend=false
terraform test
```

<details><summary>1. What does a module call look like?</summary>

A `module "name" { ... }` block. `source` says where the module's code is; every other argument
sets one of the module's variables.
</details>

<details><summary>2. Where is the module?</summary>

A relative path from this folder: up two levels to `infra/`, then into `modules/network`.
</details>

<details><summary>3. Which variables must I set?</summary>

Open `infra/modules/network/variables.tf`: any variable without a `default` is required.
There's a `local` in `main.tf` that already holds the name you want.
</details>

## Running it for real

Needs `kubectl` as well as Terraform and the AWS CLI.

```bash
export AWS_PROFILE=golf
aws sso login
cd infra/envs/dev
terraform init -backend-config="bucket=$(terraform -chdir=../../bootstrap output -raw state_bucket)"
terraform plan -out=dev.tfplan   # read it: everything should be "+" (create)
terraform apply dev.tfplan       # 15-20 minutes; EKS is slow to create
$(terraform output -raw configure_kubectl)
kubectl get nodes
terraform destroy   # when you're done for the day
```

`terraform -chdir=../../bootstrap output -raw state_bucket` reads the bucket name from the bootstrap
layer's state, so no account-specific value is written into this folder.

## The app and its monitoring

`apply` also installs two Helm charts:

| Release | Namespace | What it is |
|---|---|---|
| `kube-prometheus-stack` (`monitoring.tf`) | `monitoring` | Prometheus, Grafana, Alertmanager, node and Kubernetes metrics |
| `golf-booking` (`app.tf`, chart in [`charts/golf-booking`](../../../charts/golf-booking)) | `golf` | The four services, dev Postgres and ElasticMQ, a load generator, plus the app's ServiceMonitor, alert rules and dashboard |

The images come from ECR at the commit in `app_image_tag`. To run a newer build, find its tag
with the command in that variable's description and pass `-var app_image_tag=<sha>`.

### Look at it

```bash
terraform output -raw open_the_app            # the three port-forward commands
terraform output -raw grafana_admin_password  # Grafana login, user admin
```

- **The app:** http://localhost:8080, book a tee time.
- **Grafana:** Dashboards → **Golf booking**. The load generator keeps traffic flowing, so it's
  never empty. The built-in **Kubernetes / Compute Resources / Namespace (Pods)** dashboard with
  namespace `golf` shows the same pods from the infrastructure side.
- **Prometheus:** http://localhost:9090/targets should list `courses-api`, `bookings-api` and
  `notifications-worker` as UP. **Alerts** lists the golf-booking rules.

### Try breaking it (good for a demo)

```bash
kubectl -n golf scale deploy/courses-api --replicas=0   # bookings-api can't reach it: 5xx climb, GolfHighErrorRate fires after 5 min
kubectl -n golf scale deploy/courses-api --replicas=2   # recovers

kubectl -n golf scale deploy/notifications-worker --replicas=0   # GolfNotificationsStalled after a few minutes
kubectl -n golf scale deploy/notifications-worker --replicas=1

kubectl -n golf delete pod -l app.kubernetes.io/name=courses-api  # Kubernetes replaces them; with 2 replicas, no errors
```

The first demo needs images built after this change (`services/*/app/metrics.py` now counts
crashes as 500s). Before that, crashed requests weren't counted at all, so the error rate stayed
at 0% while customers saw errors.
