# Workflows

| Workflow | Runs | What it does |
| --- | --- | --- |
| [`ci.yml`](ci.yml) | every pull request, and every push to `main` | Lints and tests the Python services, builds all four images, and on `main` pushes them to ECR tagged with the commit SHA. |
| [`nightly-teardown.yml`](nightly-teardown.yml) | 22:00 UTC, or by hand | Destroys `infra/envs/dev` if it is running (the cost brake, [ADR 0006](../../docs/adr/0006-nightly-teardown.md)). |

Both log in to AWS with OIDC: GitHub hands the job a short-lived signed token, AWS swaps it for
temporary credentials, and no AWS keys are stored in GitHub. Each workflow gets its own role, and each
role trusts only the branch or environment it needs (`infra/bootstrap/github_oidc.tf`).

## Repository variables

Set once with `gh variable set` (they are ARNs and a bucket name, not secrets):

| Variable | Value comes from |
| --- | --- |
| `AWS_ECR_PUSH_ROLE_ARN` | `terraform -chdir=infra/bootstrap output -raw github_ecr_push_role_arn` |
| `AWS_ENV_DESTROY_ROLE_ARN` | `terraform -chdir=infra/bootstrap output -raw github_env_destroy_role_arn` |
| `TF_STATE_BUCKET` | `terraform -chdir=infra/bootstrap output -raw state_bucket` |

## Exercise: publish the images to ECR

The `build` job in `ci.yml` builds each image but stops there. Finish it by adding the steps that
publish the image, below the `# --- Exercise` comment.

What the steps must do:

1. Run **only on a push to `main`**. Pull requests build the image but never push it, and the AWS role
   (`golf-booking-github-ecr-push`) trusts only `refs/heads/main` anyway, so a PR couldn't log in.
2. Log in to AWS with OIDC using the role in the `AWS_ECR_PUSH_ROLE_ARN` variable, region `eu-west-1`.
3. Log in to ECR so `docker push` is allowed.
4. Tag the image with the full registry address and push it. The tag is the commit SHA.

You're done when a merge to `main` shows four green `Build` jobs and
`aws ecr describe-images --repository-name golf-booking/web --profile golf` lists an image tagged with
that commit's SHA.

Hints, one at a time if you need them:

- `nightly-teardown.yml` already does step 2. Compare its `permissions:` block with the one at the top
  of `ci.yml`.
- Step 1 is an `if:` on each step. GitHub sets `github.ref` and `github.event_name` for every run.
- For step 3, look at the `aws-actions/amazon-ecr-login` action, and at what it returns as an output.
- An image is pushed to wherever its name says. `golf-booking/web:abc123` names no registry, so
  Docker would try Docker Hub.
