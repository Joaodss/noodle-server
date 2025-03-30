data "google_compute_image" "container_optimized" {
  family  = var.gcp_vm_image_family
  project = var.gcp_vm_image_project
}
