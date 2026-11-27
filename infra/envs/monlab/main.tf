# Monitoring lab: a Checkmk server, a Nagios server and three hosts that both of them monitor,
# for practising a Checkmk-to-Nagios migration (ADR 0010). Ansible in monitoring-lab/ does the rest.
#
# Kept deliberately cheap: one public subnet and no NAT gateway, so each instance has a public IP
# that only admin_cidr can reach. About $0.11 an hour while up; the nightly teardown removes it.

locals {
  name = "${var.project}-${var.environment}"
}

# --- Network: one VPC, one public subnet ---

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = local.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = local.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.30.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-public" }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Firewall ---
# From outside: SSH (Ansible) and HTTP (Checkmk and Nagios web UIs and APIs), from your IP only.
# Inside the group: anything, so the servers can reach the agents (Checkmk 6556, NRPE 5666).

resource "aws_security_group" "lab" {
  name        = local.name
  description = "Monitoring lab: admin access from one IP, open between lab members"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = local.name }
}

resource "aws_vpc_security_group_ingress_rule" "admin" {
  for_each = { ssh = 22, http = 80 }

  security_group_id = aws_security_group.lab.id
  description       = "${each.key} from the admin IP"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
}

resource "aws_vpc_security_group_ingress_rule" "within_lab" {
  security_group_id            = aws_security_group.lab.id
  description                  = "Everything between lab members (agents, NRPE, ping)"
  referenced_security_group_id = aws_security_group.lab.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.lab.id
  description       = "Package downloads and the Checkmk download site"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- Servers ---

# Canonical publishes the current Ubuntu 24.04 image ID here, so no AMI ID is written in code.
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "admin" {
  key_name   = local.name
  public_key = var.ssh_public_key
}

resource "aws_instance" "server" {
  for_each = var.servers

  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = each.value.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.lab.id]
  key_name               = aws_key_pair.admin.key_name

  # IMDSv2 only: the instance metadata service needs a session token, which blocks a class of SSRF attacks.
  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = each.value.disk_gb
    volume_type = "gp3"
    encrypted   = true
  }

  # The Ansible dynamic inventory (monitoring-lab/ansible/inventory/aws_ec2.yml) builds its groups
  # from these tags, so the tags are the single list of what exists and what it is.
  tags = {
    Name              = each.key
    monlab_role       = each.value.role
    monitoring_folder = each.value.folder
  }

  # A new Ubuntu image every few weeks shouldn't rebuild the lab on the next apply.
  lifecycle {
    ignore_changes = [ami]
  }
}
