provider "google" {
  credentials           = file(var.access_credentials)
  project               = var.gcp_project
  billing_project       = var.gcp_billing_project
  region                = var.gcp_project_region
  zone                  = var.gcp_project_zone
  user_project_override = true
}
