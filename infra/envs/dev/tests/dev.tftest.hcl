# Offline check that the environment wires together: `terraform init -backend=false && terraform test`.
# Nothing is created. The AWS provider is mocked, and the EKS module is replaced by fake outputs
# because its internals are tested by its own authors. Helm is mocked too: no cluster is contacted.

mock_provider "aws" {
  mock_data "aws_ecr_repository" {
    defaults = { repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/golf-booking/web" }
  }

  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
}

mock_provider "helm" {}
mock_provider "random" {}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "golf-booking-dev"
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

run "monitoring_is_wired_up" {
  command = apply

  assert {
    condition     = helm_release.kube_prometheus_stack.namespace == "monitoring"
    error_message = "Install the monitoring stack into the monitoring namespace."
  }

  assert {
    condition     = yamldecode(helm_release.kube_prometheus_stack.values[0]).prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues == false
    error_message = "Prometheus must pick up ServiceMonitors from every chart, or the golf services won't be scraped."
  }

  assert {
    condition     = yamldecode(helm_release.golf_booking.values[0]).image.registry == "123456789012.dkr.ecr.eu-west-1.amazonaws.com"
    error_message = "The app's image registry should be the ECR host, without the repository path."
  }
}
