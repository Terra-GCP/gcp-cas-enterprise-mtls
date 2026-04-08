resource "google_privateca_certificate_authority" "root_ca" {
  project                                = var.project_id
  pool                                   = google_privateca_ca_pool.root_ca_pool.name
  gcs_bucket                             = google_storage_bucket.crl_bucket.name
  certificate_authority_id               = var.root_ca_id
  location                               = var.region
  deletion_protection                    = var.deletion_protection
  skip_grace_period                      = false
  ignore_active_certificates_on_deletion = false

  config {
    subject_config {
      subject {
        organization        = var.root_ca_organization
        organizational_unit = var.root_ca_organizational_unit
        common_name         = var.root_ca_common_name
        country_code        = var.root_ca_country
        province            = var.root_ca_state
        locality            = var.root_ca_locality
      }
    }

    x509_config {
      ca_options {
        is_ca                  = true
        max_issuer_path_length = 1
      }

      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }

        extended_key_usage {}
      }
    }
  }

  lifetime = "${var.root_ca_lifetime_years * 365 * 24 * 3600}s"

  key_spec {
    algorithm = var.root_ca_algorithm
  }

  type = "SELF_SIGNED"

  labels = var.labels

  depends_on = [
    google_storage_bucket_iam_member.crl_bucket_legacy_write,
    google_storage_bucket_iam_member.crl_bucket_ca_write,
    google_privateca_ca_pool.root_ca_pool
  ]
}