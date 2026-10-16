output "server_ip" {
  description = "EIP"
  value       = aws_eip.monitoring-eip.public_ip
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "https://${aws_eip.monitoring-eip.public_ip}"
}

output "grafana_domain" {
  description = "Grafana Domain URL"
  value       = "https://${var.domain_name}"
}
