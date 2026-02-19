output "instance_public_ip" {
  description = "Public IP of the MTProxy instance"
  value       = oci_core_instance.mtproxy.public_ip
}

output "instance_id" {
  description = "OCID of the instance"
  value       = oci_core_instance.mtproxy.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh opc@${oci_core_instance.mtproxy.public_ip}"
}

output "mtproxy_info_command" {
  description = "Command to get MTProxy connection details (run on the server)"
  value       = "/opt/mtproxy/show-connection.sh"
}

output "mtproxy_port" {
  description = "MTProxy listening port"
  value       = var.mtproxy_port
}

output "mtproxy_secret" {
  description = "MTProxy secret"
  value       = random_bytes.mtproxy_secret.hex
  sensitive   = true
}

output "telegram_proxy_link" {
  description = "Telegram proxy link - use this in Telegram to connect"
  value       = "https://t.me/proxy?server=${oci_core_instance.mtproxy.public_ip}&port=${var.mtproxy_port}&secret=${random_bytes.mtproxy_secret.hex}"
  sensitive   = true
}
