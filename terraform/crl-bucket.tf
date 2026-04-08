resource "google_project_service_identity" "privateca" {
  provider = google-beta
  project  = var.project_id
  service  = "privateca.googleapis.com"

  depends_on = [google_project_service.privateca]
}

resource "google_storage_bucket" "crl_bucket" {
  project  = var.project_id
  name     = var.crl_bucket_name
  location = var.region

  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels
  depends_on = [
    google_project_service.storage,
    google_project_service_identity.privateca,
  ]
}

resource "google_storage_bucket_iam_member" "crl_bucket_legacy_write" {
  bucket = google_storage_bucket.crl_bucket.name
  role   = "roles/storage.legacyBucketWriter"
  member = google_project_service_identity.privateca.member
}

resource "google_storage_bucket_iam_member" "crl_bucket_ca_write" {
  bucket = google_storage_bucket.crl_bucket.name
  role   = "roles/storage.objectAdmin"
  member = google_project_service_identity.privateca.member
}