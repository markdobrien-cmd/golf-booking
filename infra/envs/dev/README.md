# Dev environment

The destroyable layer: the network (your module) plus the EKS cluster. Aurora and SQS come next.
See [ADR 0005](../../../docs/adr/0005-eks-and-network-layout.md) for the reasoning.

> **Don't apply this yet.** Once up, the cluster costs roughly $0.30 an hour. The nightly
> auto-destroy and spending brake land in the next pull request; apply after that.

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

## Running it for real (after the cost-brake PR)

```bash
export AWS_PROFILE=golf
aws sso login
cd infra/envs/dev
terraform init -backend-config="bucket=$(terraform -chdir=../../bootstrap output -raw state_bucket)"
terraform plan
terraform apply     # about 15 minutes; EKS is slow to create
$(terraform output -raw configure_kubectl)
kubectl get nodes
terraform destroy   # when you're done for the day
```

`terraform -chdir=../../bootstrap output -raw state_bucket` reads the bucket name from the bootstrap
layer's state, so no account-specific value is written into this folder.
