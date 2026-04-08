resource "google_service_account" "cert_lifecycle" {
  project      = var.project_id
  account_id   = var.cert_lifecycle_sa_account_id
  display_name = "Certificate lifecycle automation"
}

resource "google_privateca_ca_pool_iam_member" "lifecycle_requester" {
  ca_pool = google_privateca_ca_pool.sub_ca_pool.id
  role    = "roles/privateca.certificateRequester"
  member  = "serviceAccount:${google_service_account.cert_lifecycle.email}"
}

resource "google_privateca_ca_pool_iam_member" "lifecycle_manager" {
  ca_pool = google_privateca_ca_pool.sub_ca_pool.id
  role    = "roles/privateca.certificateManager"
  member  = "serviceAccount:${google_service_account.cert_lifecycle.email}"
}

resource "google_storage_bucket_iam_member" "lifecycle_bucket" {
  bucket = google_storage_bucket.crl_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cert_lifecycle.email}"
}

resource "google_project_iam_member" "lifecycle_secret_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.cert_lifecycle.email}"
}

resource "google_folder_iam_member" "lifecycle_trustconfig_editor" {
  for_each = toset(var.trust_config_admin_folder_ids)
  folder   = each.value
  role     = "roles/certificatemanager.editor"
  member   = "serviceAccount:${google_service_account.cert_lifecycle.email}"
}