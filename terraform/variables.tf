variable "project_id" {
  description = "GCP project that hosts Private CA pools, CAs, and the CRL bucket."
  type        = string
}

variable "region" {
  description = "Region for Private CA resources."
  type        = string
}

variable "trust_config_admin_folder_ids" {
  description = "Folder IDs (folders/…) where workload projects live; lifecycle SA gets certificatemanager.editor."
  type        = list(string)
  default     = []
}

variable "root_ca_pool_name" {
  type = string
}

variable "sub_ca_pool_name" {
  type = string
}

variable "ca_pool_tier" {
  type    = string
  default = "ENTERPRISE"
}

variable "root_ca_id" {
  type = string
}

variable "root_ca_common_name" {
  type = string
}

variable "root_ca_organization" {
  type = string
}

variable "root_ca_organizational_unit" {
  type = string
}

variable "root_ca_country" {
  type = string
}

variable "root_ca_state" {
  type = string
}

variable "root_ca_locality" {
  type = string
}

variable "root_ca_lifetime_years" {
  type    = number
  default = 25
}

variable "root_ca_algorithm" {
  type    = string
  default = "EC_P384_SHA384"
}

variable "sub_ca_id" {
  type = string
}

variable "sub_ca_common_name" {
  type = string
}

variable "sub_ca_organization" {
  type = string
}

variable "sub_ca_organizational_unit" {
  type = string
}

variable "sub_ca_country" {
  type = string
}

variable "sub_ca_state" {
  type = string
}

variable "sub_ca_locality" {
  type = string
}

variable "sub_ca_lifetime_years" {
  type    = number
  default = 10
}

variable "sub_ca_algorithm" {
  type    = string
  default = "EC_P384_SHA384"
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "certificate_template_name" {
  type = string
}

variable "crl_bucket_name" {
  type = string
}

variable "cert_lifecycle_sa_account_id" {
  description = "Service account account_id used by automation to issue/revoke and export trust configs."
  type        = string
  default     = "sa-cert-lifecycle"
}