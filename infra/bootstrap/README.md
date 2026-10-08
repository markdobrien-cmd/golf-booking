# Bootstrap layer

The small, permanent part of the AWS setup. You create it once and leave it running; it costs well under $1 a month. Everything expensive (VPC, EKS, RDS) lives in a separate layer that is created and destroyed per working session.

| Creates | Why |
| --- | --- |
| S3 bucket for Terraform state (versioned, encrypted, private, TLS only) | Every layer stores its state here, with S3-native locking |
| One ECR repository per service (immutable tags, scan on push) | Where CI pushes images |
| GitHub OIDC provider and two IAM roles | GitHub Actions gets short-lived AWS credentials; no keys stored in GitHub |
| AWS Budgets alert (50% and 100% actual, 100% forecast) | An email before a forgotten cluster gets expensive |

21 resources in total.

## Before you start: an AWS login that isn't the root user

The email and password you signed up with are the **root user**. Use it only to set up the account, and never create access keys for it.

1. Sign in as root, turn on MFA for it (IAM > Security credentials).
2. Open **IAM Identity Center**, enable it, and create a user for yourself.
3. Create a permission set from the **AdministratorAccess** policy and assign it to your user for this account.
4. Install the tools (macOS shown; other systems have equivalents):

   ```sh
   brew install awscli
   brew install hashicorp/tap/terraform   # needs 1.10 or later
   ```

5. Log in from the terminal. Use the start URL from the Identity Center dashboard, region `eu-west-1`, and call the profile `golf`:

   ```sh
   aws configure sso
   aws sso login --profile golf
   export AWS_PROFILE=golf
   aws sts get-caller-identity   # should show your Identity Center user, not root
   ```

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
mv backend.tf.example backend.tf
terraform output -raw backend_config > backend.hcl
terraform init -migrate-state -backend-config=backend.hcl   # answer "yes"
rm terraform.tfstate terraform.tfstate.backup               # the S3 copy is now the real one
terraform plan                                              # "No changes" proves the migration worked
```

## Step 3: commit

Commit `backend.tf` and `.terraform.lock.hcl` (the lock file pins exact provider versions for everyone, CI included). `terraform.tfvars` and `backend.hcl` are git-ignored on purpose.

## Things worth understanding here

- **Why two steps?** Terraform can't store its state in a bucket that Terraform is about to create. Bootstrapping with local state and then migrating is the standard answer to this chicken-and-egg problem.
- **`prevent_destroy` on the bucket.** `terraform destroy` will refuse to delete it. Losing state means Terraform forgets what it manages.
- **The OIDC trust conditions** in `github_oidc.tf` are the security boundary. The `sub` condition is what stops any other GitHub repository from assuming these roles.
- **`terraform test`** runs against a mocked provider, so the checks in `tests/` run in CI with no AWS account at all.
