resource "google_privateca_certificate_authority" "sub_ca" {
  project                                = var.project_id
  pool                                   = google_privateca_ca_pool.sub_ca_pool.name
  gcs_bucket                             = google_storage_bucket.crl_bucket.name
  certificate_authority_id               = var.sub_ca_id
  location                               = var.region
  deletion_protection                    = var.deletion_protection
  skip_grace_period                      = true
  ignore_active_certificates_on_deletion = true

  subordinate_config {
    certificate_authority = google_privateca_certificate_authority.root_ca.name
  }

  config {
    subject_config {
      subject {
        organization        = var.sub_ca_organization
        organizational_unit = var.sub_ca_organizational_unit
        common_name         = var.sub_ca_common_name
        country_code        = var.sub_ca_country
        province            = var.sub_ca_state
        locality            = var.sub_ca_locality
      }
    }

    x509_config {
      ca_options {
        is_ca                       = true
        max_issuer_path_length      = 0
        zero_max_issuer_path_length = true
      }

      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }

        extended_key_usage {
          server_auth = true
          client_auth = true
        }
      }
    }
  }

  lifetime = "${var.sub_ca_lifetime_years * 365 * 24 * 3600}s"

  key_spec {
    algorithm = var.sub_ca_algorithm
  }

  type = "SUBORDINATE"

  labels = var.labels

  depends_on = [
    google_privateca_certificate_authority.root_ca,
    google_privateca_ca_pool.sub_ca_pool
  ]
}