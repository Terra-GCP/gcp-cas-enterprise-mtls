# Required APIs for this stack. Keeps applies predictable in greenfield projects.
resource "google_project_service" "privateca" {
  project            = var.project_id
  service            = "privateca.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}
