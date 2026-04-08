resource "google_privateca_certificate_template" "client_identity" {
  project     = var.project_id
  name        = var.certificate_template_name
  location    = var.region
  description = "Client authentication template for internal mTLS identities."

  predefined_values {
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

    cel_expression {
      expression  = "subject_alt_names.all(san, san.type == DNS || san.type == EMAIL || san.type == URI)"
      title       = "Allowed subject alternative name types"
      description = "Permit DNS, EMAIL, and URI SANs only."
    }
  }

  labels = var.labels

  depends_on = [
    google_project_service.privateca,
    google_privateca_ca_pool.sub_ca_pool,
  ]
}