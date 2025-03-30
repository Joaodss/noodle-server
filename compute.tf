resource "google_service_account" "container_host" {
  account_id   = "container-host-sa"
  display_name = "Custom SA for Container Host VM Instance"
}

resource "google_compute_disk" "container_host_boot_disk" {
  name  = "container-host-boot-disk"
  type  = "pd-standard"
  image = data.google_compute_image.container_optimized.self_link
  size  = 10
  labels = {
    managed_by = "terraform"
  }
  physical_block_size_bytes = 4096
}

resource "google_compute_disk" "container_host_data_disk" {
  name = "container-host-data-disk"
  type = "pd-standard"
  size = 20
  labels = {
    managed_by = "terraform"
  }
  physical_block_size_bytes = 4096
}

resource "google_compute_address" "static_ip" {
  name         = "ipv4-address"
  address_type = "EXTERNAL"
  region       = var.gcp_project_region
  network_tier = "STANDARD"
}

resource "google_compute_instance" "container_host" {
  name                      = "containerhost01"
  machine_type              = var.gcp_vm_size
  allow_stopping_for_update = true

  tags = var.gcp_container_host_network_tags

  boot_disk {
    source      = google_compute_disk.container_host_boot_disk.self_link
    device_name = "container-host-boot-disk_0"
  }

  attached_disk {
    source      = google_compute_disk.container_host_data_disk.self_link
    device_name = "container_host_data_disk_0"
  }

  network_interface {
    network = google_compute_network.vpc_network.name

    access_config {
      network_tier = "STANDARD"
      nat_ip       = google_compute_address.static_ip.address
    }
  }

  metadata = {
    user-data = local.cloud_config
  }

  scheduling {
    preemptible        = false
    automatic_restart  = true
    provisioning_model = "STANDARD"
  }

  service_account {
    email  = google_service_account.container_host.email
    scopes = ["cloud-platform"]
  }
}
