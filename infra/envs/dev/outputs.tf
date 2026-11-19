output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this once after apply so kubectl talks to the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "grafana_admin_password" {
  description = "Grafana login for user admin. Show it with: terraform output -raw grafana_admin_password"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "open_the_app" {
  description = "Port-forward commands for the app, Grafana and Prometheus (run each in its own terminal)."
  value       = <<-EOT
    kubectl -n golf port-forward svc/web 8080:8080                                    # http://localhost:8080
    kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80       # http://localhost:3000 (admin)
    kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090  # http://localhost:9090
  EOT
}
