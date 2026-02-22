# OCI Container Registry (OCIR) Resources

# Get tenancy namespace for OCIR
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

# Auth token for OCIR login
resource "oci_identity_auth_token" "ocir_token" {
  description = "OCIR auth token for MTProxy image"
  user_id     = var.user_ocid
}

# Container repository
resource "oci_artifacts_container_repository" "mtproxy" {
  compartment_id = var.compartment_ocid
  display_name   = "mtproxy"
  is_public      = false
}

# Outputs
output "ocir_namespace" {
  description = "OCIR namespace"
  value       = data.oci_objectstorage_namespace.ns.namespace
}

locals {
  # Region to OCIR shortcode mapping
  ocir_region_map = {
    "eu-frankfurt-1" = "fra"
    "us-ashburn-1"   = "iad"
    "us-phoenix-1"   = "phx"
    "eu-amsterdam-1" = "ams"
    "uk-london-1"    = "lhr"
  }
  ocir_region = lookup(local.ocir_region_map, var.region, var.region)
}

output "ocir_registry" {
  description = "OCIR registry URL"
  value       = "${local.ocir_region}.ocir.io"
}

output "ocir_image_url" {
  description = "Full OCIR image URL"
  value       = "${local.ocir_region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/mtproxy"
}

output "ocir_username" {
  description = "OCIR login username"
  value       = "${data.oci_objectstorage_namespace.ns.namespace}/${var.ocir_user_email}"
  sensitive   = true
}

output "ocir_token" {
  description = "OCIR auth token (use as password)"
  value       = oci_identity_auth_token.ocir_token.token
  sensitive   = true
}
