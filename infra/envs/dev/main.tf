locals {
  name = "${var.project}-${var.environment}"
}

# --- Network: written by Mark, see the exercise in README.md ---



# --- EKS cluster ---
# The community module wraps about 30 resources: the cluster, its IAM roles, security groups,
# add-ons and node groups. We configure it rather than hand-write each piece.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # Nodes and pods live in the private subnets; the control plane gets network interfaces there too.
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  # Lets kubectl on your laptop reach the API. Requests still need a valid AWS login.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  # Whoever runs `terraform apply` (your SSO role) becomes cluster admin, so no account IDs live in code.
  enable_cluster_creator_admin_permissions = true

  addons = {
    # Gives every pod a real VPC address. before_compute: it must exist before nodes join.
    vpc-cni = {
      before_compute = true
    }
    # Lets pods assume IAM roles (used later by the load balancer controller and External Secrets).
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    # Cluster-critical add-ons (DNS, load balancer controller, Argo CD): on-demand so they never vanish.
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 2
      desired_size = 1

      labels = { role = "system" }
    }

    # The golf services: Spot is far cheaper and they run as 2+ stateless copies.
    # Several instance types give AWS more spare pools to pick from, so reclaims are rarer.
    apps = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
      capacity_type  = "SPOT"

      min_size     = 1
      max_size     = 3
      desired_size = 2

      labels = { role = "apps" }
    }
  }
}
