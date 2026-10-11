output "server_ip" {
  description = "EIP"
  value       = aws_eip.monitoring-eip.public_ip
}

output "GRAFANA_URL" {
  description = "GRAFANA_URL"
  value       = "http://${aws_eip.monitoring-eip.public_ip}:3000"
}