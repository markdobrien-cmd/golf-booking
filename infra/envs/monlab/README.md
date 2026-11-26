# Monitoring lab environment

Five small EC2 instances for practising a Checkmk-to-Nagios migration
([ADR 0010](../../../docs/adr/0010-checkmk-to-nagios-lab.md)). Terraform builds the servers; Ansible in
[`monitoring-lab/`](../../../monitoring-lab/README.md) installs and configures everything on them.

| Name | Size | Role |
| --- | --- | --- |
| `cmk` | t3.medium, 20 GB | Checkmk server (site `lab`) |
| `nagios` | t3.small | Nagios server |
| `app01`, `app02` | t3.micro | monitored hosts, Checkmk folder `app` |
| `db01` | t3.micro | monitored host, Checkmk folder `db` |

> **Cost:** about $0.11 an hour while it's up (instances plus their public IPv4 addresses). No NAT
> gateway and no EKS. The [nightly teardown](../../../.github/workflows/nightly-teardown.yml) destroys it at
> 22:00 UTC if you forget.

## Why it looks like this

- **One public subnet, no NAT gateway.** A NAT gateway would cost more than the servers. Instead each
  instance has a public IP, and the security group only lets **your** IP in, on SSH (Ansible) and
  HTTP (the two web UIs). Inside the group everything is open, so the servers reach the agents.
- **Tags are the inventory.** Each instance carries `monlab_role` and `monitoring_folder` tags. The Ansible
  dynamic inventory builds its groups from them, so there's no host list to keep in step by hand.
- **No IAM roles.** Nothing on the servers calls AWS, so there's nothing to grant.

## Running it

```bash
export AWS_PROFILE=golf
aws sso login
cd infra/envs/monlab
terraform init -backend-config="bucket=$(terraform -chdir=../../bootstrap output -raw state_bucket)"

# Your IP and SSH key, passed on the command line so they're never written to a file in the repo.
terraform plan -out=monlab.tfplan \
  -var "admin_cidr=$(curl -s https://checkip.amazonaws.com)/32" \
  -var "ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
terraform apply monlab.tfplan   # about 2 minutes
terraform output
```

Then follow [`monitoring-lab/README.md`](../../../monitoring-lab/README.md). When you're done:

```bash
terraform destroy \
  -var "admin_cidr=$(curl -s https://checkip.amazonaws.com)/32" \
  -var "ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
```

If your IP changes (a new day, a different network), run `plan`/`apply` again with the new address: only
the two security group rules change.

## Offline check

```bash
terraform init -backend=false
terraform test
```
