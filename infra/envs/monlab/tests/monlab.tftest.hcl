# Offline check: `terraform init -backend=false && terraform test`. The AWS provider is mocked,
# so nothing is created.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }

  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
}

variables {
  admin_cidr     = "203.0.113.7/32"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyOnly lab"
}

run "builds_the_five_servers" {
  command = apply

  assert {
    condition     = length(aws_instance.server) == 5
    error_message = "Expected cmk, nagios and three targets."
  }

  assert {
    condition     = aws_instance.server["db01"].tags.monitoring_folder == "db" && aws_instance.server["app01"].tags.monlab_role == "targets"
    error_message = "Targets need monlab_role and monitoring_folder tags for the Ansible inventory."
  }

  assert {
    condition     = alltrue([for s in aws_instance.server : s.metadata_options[0].http_tokens == "required"])
    error_message = "Every instance should require IMDSv2."
  }
}

run "admin_access_is_one_ip_only" {
  command = apply

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.admin : r.cidr_ipv4 == "203.0.113.7/32"])
    error_message = "SSH and HTTP must only be open to admin_cidr."
  }
}

run "rejects_an_open_admin_cidr" {
  command = plan

  variables {
    admin_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.admin_cidr]
}
