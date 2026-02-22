# Generate MTProxy secret
resource "random_bytes" "mtproxy_secret" {
  length = 16
}

# Generate Secondary MTProxy secret
resource "random_bytes" "mtproxy_secret_secondary" {
  length = 16
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

# MTProxy Instance
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
      mtproxy_port              = var.mtproxy_port
      mtproxy_secret            = random_bytes.mtproxy_secret.hex
      fake_tls_domain           = var.mtproxy_fake_tls_domain
      mtproxy_port_secondary    = var.mtproxy_secondary_port
      mtproxy_secret_secondary  = random_bytes.mtproxy_secret_secondary.hex
      fake_tls_domain_secondary = var.mtproxy_secondary_domain
      ocir_username             = "${data.oci_objectstorage_namespace.ns.namespace}/${var.ocir_user_email}"
      ocir_token                = oci_identity_auth_token.ocir_token.token
      secondary_private_ip      = var.secondary_private_ip
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

# Get private IP
data "oci_core_private_ips" "mtproxy_private_ip" {
  vnic_id = data.oci_core_vnic.mtproxy_vnic.id
}

# Reserved public IP (static, persists across instance recreates)
resource "oci_core_public_ip" "mtproxy_reserved_ip" {
  compartment_id = var.compartment_ocid
  display_name   = "mtproxy-reserved-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.mtproxy_private_ip.private_ips[0].id

  freeform_tags = {
    "Purpose" = "MTProxy"
  }
}

# Secondary private IP for second proxy (static IP for OS configuration)
resource "oci_core_private_ip" "mtproxy_secondary_private_ip" {
  vnic_id      = data.oci_core_vnic.mtproxy_vnic.id
  display_name = "mtproxy-secondary-private-ip"
  ip_address   = var.secondary_private_ip
}

# Reserved public IP for secondary proxy (static, required for secondary private IPs)
resource "oci_core_public_ip" "mtproxy_secondary_ip" {
  compartment_id = var.compartment_ocid
  display_name   = "mtproxy-secondary-ip"
  lifetime       = "RESERVED"
  private_ip_id  = oci_core_private_ip.mtproxy_secondary_private_ip.id

  freeform_tags = {
    "Purpose" = "MTProxy-Secondary"
  }
}

# Note: Two proxies on same instance with different IPs
# Primary: Reserved IP, port 443, cdn.jsdelivr.net
# Secondary: Ephemeral IP, port 9443, wildberries.ru
