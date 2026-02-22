# VCN
resource "oci_core_vcn" "mtproxy_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "mtproxy-vcn"
  dns_label      = "mtproxy"
}

# Internet Gateway
resource "oci_core_internet_gateway" "mtproxy_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.mtproxy_vcn.id
  display_name   = "mtproxy-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "mtproxy_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.mtproxy_vcn.id
  display_name   = "mtproxy-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.mtproxy_igw.id
  }
}

# Security List
resource "oci_core_security_list" "mtproxy_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.mtproxy_vcn.id
  display_name   = "mtproxy-sl"

  # Egress - allow all outbound
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Ingress - SSH
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "SSH access"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress - MTProxy
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "MTProxy access"

    tcp_options {
      min = var.mtproxy_port
      max = var.mtproxy_port
    }
  }

  # Ingress - MTProxy Secondary (port 8443)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "MTProxy secondary access"

    tcp_options {
      min = 8443
      max = 8443
    }
  }
}

# Public Subnet
resource "oci_core_subnet" "mtproxy_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.mtproxy_vcn.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "mtproxy-subnet"
  dns_label                  = "mtproxysub"
  route_table_id             = oci_core_route_table.mtproxy_rt.id
  security_list_ids          = [oci_core_security_list.mtproxy_sl.id]
  prohibit_public_ip_on_vnic = false
}
