# Generate subscription token for secure access
resource "random_bytes" "subscription_token" {
  length = 16
}

# Generate VLESS UUID
resource "random_uuid" "vless_uuid" {}

# Generate x25519 private key for VLESS Reality
resource "random_bytes" "vless_reality_private_key" {
  length = 32
}

# Derive x25519 public key from private key
data "external" "vless_reality_keys" {
  program = ["python3", "${path.module}/scripts/derive-x25519-pubkey.py"]
  query = {
    private_key_hex = random_bytes.vless_reality_private_key.hex
  }
}

# Get latest Ubuntu 22.04 Minimal image
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04 Minimal"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Proxy Instance
resource "oci_core_instance" "mtproxy" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name
  display_name        = "mtproxy-server"
  shape               = var.instance_shape

  # shape_config only needed for flexible shapes
  dynamic "shape_config" {
    for_each = var.is_flexible_shape ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_gb
    }
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.mtproxy_subnet.id
    assign_public_ip = false  # Using reserved IP instead
    display_name     = "mtproxy-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      vless_port         = var.vless_port
      vless_uuid         = random_uuid.vless_uuid.result
      vless_dest_domain  = var.vless_dest_domain
      vless_private_key  = data.external.vless_reality_keys.result.private_key
      vless_public_key   = data.external.vless_reality_keys.result.public_key
      subscription_token = random_bytes.subscription_token.hex
    }))
  }

  freeform_tags = {
    "Purpose" = "MTProxy"
  }
}

# Get instance VNIC attachment
data "oci_core_vnic_attachments" "mtproxy_vnic_attachments" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.mtproxy.id
}

# Get VNIC details
data "oci_core_vnic" "mtproxy_vnic" {
  vnic_id = data.oci_core_vnic_attachments.mtproxy_vnic_attachments.vnic_attachments[0].vnic_id
}

# Get primary private IP (filter to avoid picking secondary)
data "oci_core_private_ips" "mtproxy_primary_private_ip" {
  vnic_id = data.oci_core_vnic.mtproxy_vnic.id

  filter {
    name   = "is_primary"
    values = ["true"]
  }
}

# Reserved public IP (static, persists across instance recreates)
resource "oci_core_public_ip" "mtproxy_reserved_ip" {
  compartment_id = var.compartment_ocid
  display_name   = "mtproxy-reserved-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.mtproxy_primary_private_ip.private_ips[0].id

  freeform_tags = {
    "Purpose" = "MTProxy"
  }
}
