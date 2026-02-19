# ASCII to hex lookup for domain encoding
locals {
  ascii_hex = {
    "a" = "61", "b" = "62", "c" = "63", "d" = "64", "e" = "65", "f" = "66", "g" = "67",
    "h" = "68", "i" = "69", "j" = "6a", "k" = "6b", "l" = "6c", "m" = "6d", "n" = "6e",
    "o" = "6f", "p" = "70", "q" = "71", "r" = "72", "s" = "73", "t" = "74", "u" = "75",
    "v" = "76", "w" = "77", "x" = "78", "y" = "79", "z" = "7a",
    "A" = "41", "B" = "42", "C" = "43", "D" = "44", "E" = "45", "F" = "46", "G" = "47",
    "H" = "48", "I" = "49", "J" = "4a", "K" = "4b", "L" = "4c", "M" = "4d", "N" = "4e",
    "O" = "4f", "P" = "50", "Q" = "51", "R" = "52", "S" = "53", "T" = "54", "U" = "55",
    "V" = "56", "W" = "57", "X" = "58", "Y" = "59", "Z" = "5a",
    "0" = "30", "1" = "31", "2" = "32", "3" = "33", "4" = "34",
    "5" = "35", "6" = "36", "7" = "37", "8" = "38", "9" = "39",
    "." = "2e", "-" = "2d", "_" = "5f"
  }
  domain_hex = join("", [for c in split("", var.mtproxy_fake_tls_domain) : local.ascii_hex[c]])
  fake_tls_secret = "ee${random_bytes.mtproxy_secret.hex}${local.domain_hex}"
}

output "instance_public_ip" {
  description = "Reserved public IP of the MTProxy instance (static)"
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

output "mtproxy_port" {
  description = "MTProxy listening port"
  value       = var.mtproxy_port
}

output "mtproxy_secret" {
  description = "MTProxy base secret (without fake-TLS prefix)"
  value       = random_bytes.mtproxy_secret.hex
  sensitive   = true
}

output "mtproxy_fake_tls_secret" {
  description = "MTProxy fake-TLS secret (use this one for better speed in Russia)"
  value       = local.fake_tls_secret
  sensitive   = true
}

output "fake_tls_domain" {
  description = "Domain used for fake-TLS disguise"
  value       = var.mtproxy_fake_tls_domain
}

output "telegram_proxy_link" {
  description = "Telegram proxy link with fake-TLS - use this in Telegram"
  value       = "https://t.me/proxy?server=${oci_core_public_ip.mtproxy_reserved_ip.ip_address}&port=${var.mtproxy_port}&secret=${local.fake_tls_secret}"
  sensitive   = true
}
