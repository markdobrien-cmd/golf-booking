variable "name" {
  description = "Prefix for resource names, for example golf-booking-dev."
  type        = string
}

variable "cidr" {
  description = "Address range for the whole VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "How many Availability Zones to spread across. EKS needs at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 Availability Zones."
  }
}
