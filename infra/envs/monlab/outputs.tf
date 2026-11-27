output "public_ips" {
  description = "Public IP of each server."
  value       = { for name, server in aws_instance.server : name => server.public_ip }
}

output "checkmk_url" {
  description = "Checkmk web UI (user cmkadmin; password in monitoring-lab/ansible/.secrets/cmkadmin after the first playbook run)."
  value       = "http://${aws_instance.server["cmk"].public_ip}/lab/"
}

output "nagios_url" {
  description = "Nagios web UI (user nagiosadmin; password in monitoring-lab/ansible/.secrets/nagiosadmin)."
  value       = "http://${aws_instance.server["nagios"].public_ip}/nagios4/"
}

output "ssh" {
  description = "SSH command for each server."
  value       = { for name, server in aws_instance.server : name => "ssh ubuntu@${server.public_ip}" }
}
