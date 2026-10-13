# Bootstrap layer

The small, permanent part of the AWS setup. You create it once and leave it running; it costs well under $1 a month. Everything expensive (VPC, EKS, RDS) lives in a separate layer that is created and destroyed per working session.

| Creates | Why |
| --- | --- |
| S3 bucket for Terraform state (versioned, encrypted, private, TLS only) | Every layer stores its state here, with S3-native locking |
| One ECR repository per service (immutable tags, scan on push) | Where CI pushes images |
| GitHub OIDC provider and three IAM roles (image push, plan, nightly teardown) | GitHub Actions gets short-lived AWS credentials; no keys stored in GitHub |
| AWS Budgets alert (50% and 100% actual, 100% forecast) | An email before a forgotten cluster gets expensive |

24 resources in total.

## Before you start: an AWS login that isn't the root user

The email and password you signed up with are the **root user**. Use it only to set up the account, and never create access keys for it.

1. Sign in as root, turn on MFA for it (IAM > Security credentials).
2. Open **IAM Identity Center**, enable it, and create a user for yourself.
3. Create a permission set from the **AdministratorAccess** policy and assign it to your user for this account.
4. Install the tools (Terraform 1.10 or later):

   ```sh
   # Windows (then open a new PowerShell window)
   winget install Git.Git Hashicorp.Terraform Amazon.AWSCLI
   # macOS
   brew install awscli hashicorp/tap/terraform
   ```

   None of this needs an Administrator shell.

5. Log in from the terminal. Use the start URL from the Identity Center dashboard, region `eu-west-1`, and call the profile `golf`:

   ```sh
   aws configure sso
   aws sso login --profile golf
   export AWS_PROFILE=golf
   aws sts get-caller-identity   # should show your Identity Center user, not root
   ```

On Windows PowerShell, use `$env:AWS_PROFILE = "golf"` instead of `export`.

## Step 1: create the bootstrap resources (local state)

The state bucket doesn't exist yet, so this first run keeps state on your laptop.

```sh
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set budget_email
terraform init
terraform test     # offline checks with a mocked AWS provider
terraform plan     # read it: expect "21 to add, 0 to change, 0 to destroy"
terraform apply
```

## Step 2: move the state into S3

```sh
terraform output -raw backend_config > backend.hcl          # read the bucket details while state is still local
mv backend.tf.example backend.tf                            # only now switch the backend to S3
terraform init -migrate-state -backend-config=backend.hcl   # answer "yes"
rm terraform.tfstate terraform.tfstate.backup               # the S3 copy is now the real one
terraform plan                                              # "No changes" proves the migration worked
```

On Windows PowerShell, write the backend file with `terraform output -raw backend_config | Out-File -Encoding ascii backend.hcl` (a plain `>` writes UTF-16, which Terraform can't parse), and delete the local state with `rm terraform.tfstate, terraform.tfstate.backup`.

## Step 3: commit

Commit `backend.tf` and `.terraform.lock.hcl` (the lock file pins exact provider versions for everyone, CI included). `terraform.tfvars` and `backend.hcl` are git-ignored on purpose.

## Step 4: switch on the nightly teardown (cost brake)

Added after the first apply, so this is also your first *change* to existing infrastructure.
`.github/workflows/nightly-teardown.yml` destroys `infra/envs/dev` every night at 22:00 UTC if
anything is still running. It needs a role in AWS and two repository variables in GitHub.

```bash
cd infra/bootstrap
git checkout main && git pull
terraform plan    # expect 3 to add: the role, its policy attachment and its inline policy
terraform apply

gh variable set AWS_ENV_DESTROY_ROLE_ARN --body "$(terraform output -raw github_env_destroy_role_arn)"
gh variable set TF_STATE_BUCKET --body "$(terraform output -raw state_bucket)"
```

These are *variables*, not secrets: a role ARN and a bucket name are useless without the OIDC
trust, so they don't need hiding. Then try it by hand; with nothing running it should say
"Resources in state: 0" and stop:

```bash
gh workflow run "Nightly dev teardown"
gh run watch
```

## Things worth understanding here

- **Why two steps?** Terraform can't store its state in a bucket that Terraform is about to create. Bootstrapping with local state and then migrating is the standard answer to this chicken-and-egg problem.
- **`prevent_destroy` on the bucket.** `terraform destroy` will refuse to delete it. Losing state means Terraform forgets what it manages.
- **The OIDC trust conditions** in `github_oidc.tf` are the security boundary. The `sub` condition is what stops any other GitHub repository from assuming these roles.
- **`terraform test`** runs against a mocked provider, so the checks in `tests/` run in CI with no AWS account at all.
- **The teardown role is broad** (PowerUserAccess plus deleting IAM resources tagged `project = golf-booking`), because destroying EKS touches many services. Its trust policy is the real limit: only a job in the `dev-teardown` GitHub environment of this repository can assume it. See [ADR 0006](../../docs/adr/0006-nightly-teardown.md).
