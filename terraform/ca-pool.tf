resource "google_privateca_ca_pool" "root_ca_pool" {
  project  = var.project_id
  name     = var.root_ca_pool_name
  location = var.region
  tier     = var.ca_pool_tier

  publishing_options {
    publish_ca_cert = true
    publish_crl     = true
  }

  labels = var.labels

  depends_on = [
    google_project_service.privateca,
    google_storage_bucket_iam_member.crl_bucket_ca_write,
    google_storage_bucket_iam_member.crl_bucket_legacy_write,
  ]
}

resource "google_privateca_ca_pool" "sub_ca_pool" {
  project  = var.project_id
  name     = var.sub_ca_pool_name
  location = var.region
  tier     = var.ca_pool_tier

  publishing_options {
    publish_ca_cert = true
    publish_crl     = true
  }

  issuance_policy {
    maximum_lifetime = "63072000s"

    baseline_values {
      ca_options {
        is_ca = false
      }

      key_usage {
        base_key_usage {
          digital_signature = true
          key_encipherment  = true
        }

        extended_key_usage {
          client_auth = true
        }
      }
    }

    identity_constraints {
      allow_subject_passthrough           = true
      allow_subject_alt_names_passthrough = true
    }
  }

  labels = var.labels

  depends_on = [
    google_project_service.privateca,
    google_privateca_ca_pool.root_ca_pool,
  ]
}