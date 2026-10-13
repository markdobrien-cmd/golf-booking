# The spec for the network module. Runs offline: `terraform init && terraform test` in infra/modules/network.
# The AWS provider is mocked, so nothing is created and no login is needed.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
}

variables {
  name = "golf-booking-dev"
}

run "one_public_and_one_private_subnet_per_zone" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Expected 2 public and 2 private subnets (one of each per Availability Zone)."
  }

  assert {
    condition     = [for s in aws_subnet.public : s.availability_zone] == ["eu-west-1a", "eu-west-1b"]
    error_message = "Public subnets should be in eu-west-1a and eu-west-1b, one each."
  }

  assert {
    condition     = [for s in aws_subnet.private : s.availability_zone] == ["eu-west-1a", "eu-west-1b"]
    error_message = "Private subnets should be in eu-west-1a and eu-west-1b, one each."
  }
}

run "address_ranges" {
  command = plan

  assert {
    condition     = [for s in aws_subnet.private : s.cidr_block] == ["10.0.0.0/19", "10.0.32.0/19"]
    error_message = "Private subnets should be the large /19 ranges 10.0.0.0/19 and 10.0.32.0/19 (pods use many addresses)."
  }

  assert {
    condition     = [for s in aws_subnet.public : s.cidr_block] == ["10.0.240.0/24", "10.0.241.0/24"]
    error_message = "Public subnets should be the small /24 ranges 10.0.240.0/24 and 10.0.241.0/24 (only load balancers live there)."
  }
}

run "only_public_subnets_hand_out_public_ips" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch])
    error_message = "Public subnets should set map_public_ip_on_launch = true."
  }

  assert {
    condition     = !anytrue([for s in aws_subnet.private : coalesce(s.map_public_ip_on_launch, false)])
    error_message = "Private subnets must never hand out public IP addresses."
  }
}

run "tagged_for_the_load_balancer_controller" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets need the tag kubernetes.io/role/elb = \"1\" so EKS puts internet-facing load balancers there."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Private subnets need the tag kubernetes.io/role/internal-elb = \"1\"."
  }
}

run "three_zones_when_asked" {
  command = plan

  variables {
    az_count = 3
  }

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3
    error_message = "Setting az_count = 3 should give 3 public and 3 private subnets."
  }
}
