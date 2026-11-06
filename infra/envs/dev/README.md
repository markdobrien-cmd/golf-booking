# Dev environment

The destroyable layer: the network (your module), the EKS cluster and an Aurora MySQL learning
cluster ([ADR 0008](../../../docs/adr/0008-aurora-mysql-serverless.md)). Aurora PostgreSQL and SQS come next.
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

## Exercise: add a failover reader

Today the Aurora MySQL cluster has one instance, so the console shows **Multi-AZ: No** and a failed
writer means about 10 minutes of downtime while Aurora rebuilds it. With a second instance
(a reader), Aurora promotes it in about 30 seconds instead.

Add a resource named `aws_rds_cluster_instance.mysql_reader` to `aurora_mysql.tf`. The last run in
`tests/dev.tftest.hcl` checks it. Run it offline as above (`terraform init -backend=false && terraform test`).

<details><summary>1. Where do I start?</summary>

Look at the existing `aws_rds_cluster_instance "mysql"`. A reader is the same kind of resource
joined to the same cluster. Aurora decides which instance is the writer; you don't mark it.
</details>

<details><summary>2. Why not just add <code>count = 2</code> to the existing instance?</summary>

`count` changes the resource's address in state from `aws_rds_cluster_instance.mysql` to
`aws_rds_cluster_instance.mysql[0]`. Terraform then sees the old one as deleted and a new one as
created, and the plan replaces your writer. Use a separate resource (or a `moved` block if you
really want `count`).
</details>

<details><summary>3. What's <code>promotion_tier</code>?</summary>

It ranks readers for failover, from 0 (first choice) to 15. On Serverless v2, readers in tier 0 or 1
also scale up with the writer, so they're ready to take its load the moment they're promoted.
</details>

<details><summary>4. Before you apply</summary>

`terraform plan` should show exactly **1 to add, 0 to change, 0 to destroy**. Anything touching the
writer means something's wrong. After apply, check the Multi-AZ column and each instance's AZ with:

```bash
aws rds describe-db-clusters --db-cluster-identifier golf-booking-dev-mysql \
  --query 'DBClusters[0].DBClusterMembers[].[DBInstanceIdentifier,IsClusterWriter]' --output table
aws rds describe-db-instances --filters Name=db-cluster-id,Values=golf-booking-dev-mysql \
  --query 'DBInstances[].[DBInstanceIdentifier,AvailabilityZone]' --output table
```

If both landed in the same AZ, set `availability_zone` on the **reader only** (on the writer it
forces a replacement). Then try `aws rds failover-db-cluster --db-cluster-identifier golf-booking-dev-mysql`
and watch the roles swap.
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

## Trying the Aurora MySQL cluster

The database is private, so connect from a throwaway pod inside the cluster. The password is in
Secrets Manager; nothing is stored on disk.

```bash
SECRET=$(aws secretsmanager get-secret-value --secret-id "$(terraform output -raw mysql_secret_arn)" \
  --query SecretString --output text)
kubectl run mysql-client --rm -it --restart=Never --image=mysql:8.0 \
  --env MYSQL_PWD="$(echo "$SECRET" | jq -r .password)" -- \
  mysql -h "$(terraform output -raw mysql_endpoint)" -u golfadmin golf -e 'SELECT VERSION();'
```

Or skip the pod and use the Data API (SQL over HTTPS, checked by IAM). The console's
RDS **Query editor** uses the same API: pick the cluster, choose "Connect with a Secrets Manager ARN"
and paste `terraform output -raw mysql_secret_arn`.

```bash
aws rds-data execute-statement --database golf --sql 'SELECT VERSION();' \
  --resource-arn "$(aws rds describe-db-clusters --db-cluster-identifier golf-booking-dev-mysql --query 'DBClusters[0].DBClusterArn' --output text)" \
  --secret-arn "$(terraform output -raw mysql_secret_arn)"
```

If the cluster has paused (no connections for 5 minutes), the first query takes about 15 seconds.
