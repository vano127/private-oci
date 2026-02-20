# OCI Provider Variables
variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "fingerprint" {
  description = "OCI API Key Fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API private key"
  type        = string
}

variable "region" {
  description = "OCI Region"
  type        = string
}

variable "compartment_ocid" {
  description = "OCI Compartment OCID"
  type        = string
}

# Instance Variables
variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "instance_shape" {
  description = "Instance shape"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "is_flexible_shape" {
  description = "Whether the shape is flexible (requires shape_config)"
  type        = bool
  default     = false
}

variable "instance_ocpus" {
  description = "Number of OCPUs for flexible shape"
  type        = number
  default     = 1
}

variable "instance_memory_gb" {
  description = "Memory in GB for flexible shape"
  type        = number
  default     = 1
}

# MTProxy Variables
variable "mtproxy_port" {
  description = "MTProxy listening port"
  type        = number
  default     = 443
}

variable "mtproxy_fake_tls_domain" {
  description = "Domain to impersonate for fake-TLS (helps bypass throttling)"
  type        = string
  default     = "bart.dnslist.site"
}
