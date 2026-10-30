# 0007: CI builds every service and publishes images tagged with the commit SHA

**Status:** accepted, 2026-10-30

## Context
Nothing built or tested the services automatically, and nothing put images into the ECR repositories
created in Phase 1. Argo CD (Phase 6) will deploy whatever image tag Git names, so the images it
pulls must be traceable to one commit and must have passed their tests.

## Decision
One workflow, `.github/workflows/ci.yml`:

- **On every pull request:** lint and unit-test the three Python services, and build all four images
  without pushing them. A broken Dockerfile fails the PR, not the merge.
- **On every push to `main`:** the same, then push each image to ECR tagged with the full commit SHA.
- Pushing uses OIDC through the existing `golf-booking-github-ecr-push` role, which trusts only
  `refs/heads/main` and can only push to this project's repositories.
- The ECR repositories are immutable, so a SHA tag can never be overwritten and always means the same
  image.

### Alternatives considered
- **A `latest` tag:** easy, but you can't tell what is running or roll back to a known version, and
  Argo CD can't see a change when the tag name doesn't change.
- **Build only the services whose files changed:** faster and cheaper as the repository grows, but
  more logic to get wrong. With four small services, building everything takes a couple of minutes.
- **A separate workflow per service:** clearer ownership in a large team, but four copies of the same
  steps to keep in step. A matrix keeps one definition.

## Consequences
- Every merge pushes four images, even when only one service changed. The ECR lifecycle policy keeps
  the newest 20 per repository, so storage stays small.
- Deployment is not part of CI. Phase 6 adds a step that writes the new tag into the GitOps
  repository, and Argo CD deploys from there.
