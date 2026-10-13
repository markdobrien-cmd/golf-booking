output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Subnets for the internet-facing load balancer."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Subnets for EKS nodes and the database."
  value       = aws_subnet.private[*].id
}
