output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this once after apply so kubectl talks to the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "mysql_endpoint" {
  description = "Writer endpoint of the Aurora MySQL cluster (reachable only from inside the VPC)."
  value       = aws_rds_cluster.mysql.endpoint
}

output "mysql_secret_arn" {
  description = "Secrets Manager secret holding the MySQL admin username and password."
  value       = aws_rds_cluster.mysql.master_user_secret[0].secret_arn
}

output "grafana_admin_password" {
  description = "Grafana login for user admin. Show it with: terraform output -raw grafana_admin_password"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "mysql_exporter_password" {
  description = "Password for the MySQL 'exporter' user (README, Monitoring). Show it with: terraform output -raw mysql_exporter_password"
  value       = random_password.mysql_exporter.result
  sensitive   = true
}
