resource "google_project_service" "project" {
  for_each = toset(var.gcp_project_enabled_services)
  project  = data.google_project.project.id
  service  = each.key

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_on_destroy = false
}
