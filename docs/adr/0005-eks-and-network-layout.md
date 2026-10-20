# 0005: EKS cluster and network layout

**Status:** accepted, 2026-10-13

## Context
The services need a Kubernetes cluster that is cheap enough to create and destroy every session,
but shaped like a production setup so it is worth talking about in interviews.

## Decision
- **Own network module** (`infra/modules/network`): one VPC across 2 Availability Zones, a public /24
  per zone for the load balancer only, a private /19 per zone for nodes, pods and the database, and a
  single NAT gateway. Private subnets are large because the VPC CNI gives every pod a VPC address.
- **Community EKS module** (`terraform-aws-modules/eks/aws` v21): it wraps about 30 resources
  (IAM, security groups, add-ons, node groups) that are well tested elsewhere. Writing the network by
  hand and the cluster through a module shows both skills.
- **Two managed node groups:** `system` on on-demand `t3.medium` for cluster-critical add-ons
  (CoreDNS, load balancer controller, Argo CD), and `apps` on Spot across several instance types for
  the stateless services.
- **Cluster access** comes from EKS access entries: whoever applies becomes admin, so no account IDs
  or role ARNs are committed.
- **Database:** Aurora Serverless v2 (PostgreSQL) in the private subnets, able to scale to zero.
  Not Aurora DSQL: bookings-api relies on `pg_advisory_xact_lock` to prevent double bookings, which
  DSQL does not support.

## Consequences
- One NAT gateway is a single point of failure for outbound traffic; accepted for a demo to halve its cost.
- Spot nodes can be reclaimed with 2 minutes' notice, so every app runs at least 2 replicas.
- The API endpoint is public (still behind AWS authentication) so kubectl works from a laptop;
  `api_allowed_cidrs` can narrow it to one IP.
