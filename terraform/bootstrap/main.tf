terraform {
  required_version = ">= 1.0.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Get Object Storage namespace
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

# Create bucket for Terraform state
resource "oci_objectstorage_bucket" "terraform_state" {
  compartment_id = var.tenancy_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "terraform-state"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"

  freeform_tags = {
    "Purpose" = "Terraform State"
  }
}

# Create Customer Secret Key for S3 compatibility
resource "oci_identity_customer_secret_key" "terraform_s3" {
  display_name = "terraform-s3-backend"
  user_id      = var.user_ocid
}

# Variables
variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key_path" {
  type = string
}

variable "region" {
  type = string
}

# Outputs
output "namespace" {
  value = data.oci_objectstorage_namespace.ns.namespace
}

output "bucket_name" {
  value = oci_objectstorage_bucket.terraform_state.name
}

output "s3_endpoint" {
  value = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
}

output "s3_access_key" {
  value = oci_identity_customer_secret_key.terraform_s3.id
}

output "s3_secret_key" {
  value     = oci_identity_customer_secret_key.terraform_s3.key
  sensitive = true
}
