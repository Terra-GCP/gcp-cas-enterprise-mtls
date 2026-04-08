output "sub_ca_pool_id" {
  description = "Issuing pool resource id."
  value       = google_privateca_ca_pool.sub_ca_pool.id
}

output "sub_ca_name" {
  description = "Subordinate CA name for gcloud (issuer flag)."
  value       = google_privateca_certificate_authority.sub_ca.name
}

output "certificate_template_name" {
  value = google_privateca_certificate_template.client_identity.name
}

output "crl_bucket" {
  value = google_storage_bucket.crl_bucket.name
}

output "cert_lifecycle_service_account_email" {
  value = google_service_account.cert_lifecycle.email
}

output "project_number" {
  description = "Convenience for IAM bindings."
  value       = data.google_project.current.number
}