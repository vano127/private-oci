output "instance_public_ip" {
  description = "Reserved public IP of the instance (static)"
  value       = oci_core_public_ip.mtproxy_reserved_ip.ip_address
}

output "instance_id" {
  description = "OCID of the instance"
  value       = oci_core_instance.mtproxy.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ubuntu@${oci_core_public_ip.mtproxy_reserved_ip.ip_address}"
}

# VLESS + Reality outputs
output "vless_port" {
  description = "VLESS + Reality listening port"
  value       = var.vless_port
}

output "vless_uuid" {
  description = "VLESS user UUID"
  value       = random_uuid.vless_uuid.result
  sensitive   = true
}

output "vless_dest_domain" {
  description = "Reality destination domain (SNI)"
  value       = var.vless_dest_domain
}

output "vless_public_key" {
  description = "Reality x25519 public key"
  value       = data.external.vless_reality_keys.result.public_key
  sensitive   = true
}

output "vless_link" {
  description = "Complete VLESS + Reality share link (works in v2rayNG, Hiddify, Streisand)"
  value       = "vless://${random_uuid.vless_uuid.result}@${oci_core_public_ip.mtproxy_reserved_ip.ip_address}:${var.vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${var.vless_dest_domain}&fp=chrome&pbk=${data.external.vless_reality_keys.result.public_key}&sid=0123456789abcdef&type=tcp#OCI-VLESS-Reality"
  sensitive   = true
}

output "hiddify_import_link" {
  description = "Hiddify deep link - tap on phone to import VLESS config directly into Hiddify"
  value       = "hiddify://import/vless://${random_uuid.vless_uuid.result}@${oci_core_public_ip.mtproxy_reserved_ip.ip_address}:${var.vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${var.vless_dest_domain}&fp=chrome&pbk=${data.external.vless_reality_keys.result.public_key}&sid=0123456789abcdef&type=tcp#OCI-VLESS-Reality"
  sensitive   = true
}

output "v2raytun_import_link" {
  description = "v2raytun deep link - tap on phone to import VLESS config directly into v2raytun"
  value       = "v2raytun://import/vless://${random_uuid.vless_uuid.result}@${oci_core_public_ip.mtproxy_reserved_ip.ip_address}:${var.vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${var.vless_dest_domain}&fp=chrome&pbk=${data.external.vless_reality_keys.result.public_key}&sid=0123456789abcdef&type=tcp#OCI-VLESS-Reality"
  sensitive   = true
}

# Subscription outputs (v2raytun with Telegram-only routing)
output "subscription_token" {
  description = "Secret token for subscription URL access"
  value       = random_bytes.subscription_token.hex
  sensitive   = true
}

output "subscription_url" {
  description = "Subscription URL with Telegram-only routing (share with users)"
  value       = "http://${oci_core_public_ip.mtproxy_reserved_ip.ip_address}:8080/sub/${random_bytes.subscription_token.hex}"
  sensitive   = true
}

output "v2raytun_subscription_link" {
  description = "v2raytun deep link for subscription with Telegram-only routing (use in QR code)"
  value       = "v2raytun://import/http://${oci_core_public_ip.mtproxy_reserved_ip.ip_address}:8080/sub/${random_bytes.subscription_token.hex}"
  sensitive   = true
}
