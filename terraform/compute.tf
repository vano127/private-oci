# Generate MTProxy secret
resource "random_bytes" "mtproxy_secret" {
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
    assign_public_ip = true
    display_name     = "mtproxy-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      mtproxy_port   = var.mtproxy_port
      mtproxy_secret = random_bytes.mtproxy_secret.hex
    }))
  }

  freeform_tags = {
    "Purpose" = "MTProxy"
  }
}
