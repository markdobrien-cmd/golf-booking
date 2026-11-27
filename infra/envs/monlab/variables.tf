variable "region" {
  description = "AWS region for the lab."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "golf-booking"
}

variable "environment" {
  description = "Environment name, used in resource names and tags."
  type        = string
  default     = "monlab"
}

variable "admin_cidr" {
  description = "Your own public IP as x.x.x.x/32 (curl -s https://checkip.amazonaws.com). Only this address can reach SSH and the two web UIs."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "Use a real address range such as 203.0.113.7/32, not 0.0.0.0/0."
  }
}

variable "ssh_public_key" {
  description = "Contents of your SSH public key (for example ~/.ssh/id_ed25519.pub). Ansible logs in as ubuntu with it."
  type        = string
}

# One entry per server. "role" becomes the Ansible group; "folder" is the Checkmk folder (and the
# Ansible group whose group_vars hold that folder's Nagios checks).
variable "servers" {
  description = "The lab's EC2 instances."
  type = map(object({
    instance_type = string
    role          = string
    folder        = optional(string, "")
    disk_gb       = optional(number, 10)
  }))
  default = {
    cmk    = { instance_type = "t3.medium", role = "checkmk_server", disk_gb = 20 }
    nagios = { instance_type = "t3.small", role = "nagios_server" }
    app01  = { instance_type = "t3.micro", role = "targets", folder = "app" }
    app02  = { instance_type = "t3.micro", role = "targets", folder = "app" }
    db01   = { instance_type = "t3.micro", role = "targets", folder = "db" }
  }
}
