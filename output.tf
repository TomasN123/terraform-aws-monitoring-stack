output "SERVER_IP" {
  description = "EIP"
  value       = aws_eip.monitoring-eip.public_ip
}

output "GRAFANA_IP_URL" {
  description = "GRAFANA_URL"
  value       = "http://${aws_eip.monitoring-eip.public_ip}:3000"
}

output "GRAFANA_HOSTNAME_URL" {
  description = "GRAFANA_URL"
  value       = "https://cloud-telemetry.click"
}