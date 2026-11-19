# Offline check that the environment wires together: `terraform init -backend=false && terraform test`.
# Nothing is created. The AWS provider is mocked, and the EKS module is replaced by fake outputs
# because its internals are tested by its own authors. Helm is mocked too: no cluster is contacted.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }

  # Mocks return random strings; IAM resources insist on valid JSON.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }

  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }

  # RDS fills in the admin-password secret when the cluster is created; the mock has to pretend it did.
  mock_resource "aws_rds_cluster" {
    defaults = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds-mock" }]
    }
  }
}

mock_provider "helm" {}
mock_provider "random" {}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "golf-booking-dev"
    node_security_group_id             = "sg-0nodes"
    cluster_endpoint                   = "https://example.eks.amazonaws.com"
    cluster_certificate_authority_data = "Y2VydA=="
  }
}

run "network_is_wired_in" {
  # "apply" against mocks: nothing real happens, but every value gets filled in so we can check it.
  command = apply

  assert {
    condition     = length(module.network.private_subnet_ids) == 2 && length(module.network.public_subnet_ids) == 2
    error_message = "Call the network module so it builds 2 public and 2 private subnets."
  }

  assert {
    condition     = output.configure_kubectl == "aws eks update-kubeconfig --region eu-west-1 --name golf-booking-dev"
    error_message = "configure_kubectl output should point at the golf-booking-dev cluster."
  }
}

run "aurora_mysql_is_private_and_serverless" {
  command = apply

  assert {
    condition     = aws_rds_cluster.mysql.engine == "aurora-mysql" && aws_rds_cluster_instance.mysql.instance_class == "db.serverless"
    error_message = "Aurora MySQL should run on a db.serverless (Serverless v2) instance."
  }

  assert {
    condition     = toset(aws_db_subnet_group.mysql.subnet_ids) == toset(module.network.private_subnet_ids)
    error_message = "The database belongs in the private subnets only."
  }

  assert {
    condition     = aws_rds_cluster_instance.mysql.publicly_accessible == false && aws_rds_cluster.mysql.storage_encrypted
    error_message = "The database must be private and encrypted."
  }

  assert {
    condition     = aws_rds_cluster.mysql.enable_http_endpoint
    error_message = "Enable the Data API so the Query Editor and aws rds-data work."
  }

  assert {
    condition     = aws_rds_cluster.mysql.database_insights_mode == "advanced" && aws_rds_cluster.mysql.performance_insights_retention_period == 465
    error_message = "Advanced Database Insights needs Performance Insights with 465 days of retention."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.mysql_from_nodes.referenced_security_group_id == "sg-0nodes" && aws_vpc_security_group_ingress_rule.mysql_from_nodes.from_port == 3306
    error_message = "Only the EKS nodes should reach MySQL on port 3306."
  }
}

# Exercise (see README.md): add a reader so the cluster can fail over in seconds.
run "aurora_mysql_has_a_failover_reader" {
  command = apply

  assert {
    condition     = aws_rds_cluster_instance.mysql_reader.cluster_identifier == aws_rds_cluster.mysql.id
    error_message = "The reader must join the existing aws_rds_cluster.mysql cluster."
  }

  assert {
    condition     = aws_rds_cluster_instance.mysql_reader.instance_class == "db.serverless"
    error_message = "The reader should be a Serverless v2 instance, like the writer."
  }

  assert {
    condition     = aws_rds_cluster_instance.mysql_reader.identifier != aws_rds_cluster_instance.mysql.identifier
    error_message = "Each instance needs its own identifier."
  }

  assert {
    condition     = aws_rds_cluster_instance.mysql_reader.promotion_tier <= 1
    error_message = "Use promotion tier 0 or 1 so the reader scales with the writer and is ready to take over."
  }

  assert {
    condition     = aws_rds_cluster_instance.mysql_reader.publicly_accessible == false
    error_message = "The reader must stay private, like the writer."
  }
}

run "monitoring_is_wired_up" {
  command = apply

  assert {
    condition     = aws_eks_pod_identity_association.yace.namespace == helm_release.yace.namespace && aws_eks_pod_identity_association.yace.service_account == yamldecode(helm_release.yace.values[0]).serviceAccount.name
    error_message = "YACE's service account must match its Pod Identity association, or it gets no AWS credentials."
  }

  assert {
    condition     = contains(flatten([for p in data.aws_iam_policy_document.yace_trust.statement[0].principals : p.identifiers]), "pods.eks.amazonaws.com")
    error_message = "The YACE role must trust EKS Pod Identity."
  }

  assert {
    condition     = yamldecode(helm_release.mysql_exporter[0].values[0]).mysql.host == aws_rds_cluster.mysql.endpoint
    error_message = "mysqld_exporter should use the writer (cluster) endpoint so it follows failovers."
  }

  assert {
    condition     = length(yamldecode(helm_release.kube_prometheus_stack.values[0]).additionalPrometheusRulesMap.aurora-mysql.groups[0].rules) >= 2
    error_message = "Keep the Aurora alert rules alongside the stack."
  }
}
