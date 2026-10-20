# Offline check that the environment wires together: `terraform init -backend=false && terraform test`.
# Nothing is created. The AWS provider is mocked, and the EKS module is replaced by fake outputs
# because its internals are tested by its own authors.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
}

override_module {
  target  = module.eks
  outputs = { cluster_name = "golf-booking-dev" }
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
