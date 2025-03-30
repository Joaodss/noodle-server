gcp_vm_size                     = "e2-micro"
gcp_vm_image_family             = "cos-117-lts"
gcp_vm_image_project            = "cos-cloud"
gcp_container_host_network_tags = ["http-server", "https-server", "https-server-udp", "allow-ssh-proxy"]
gcp_project_enabled_services = [
  "cloudbilling.googleapis.com",
  "cloudresourcemanager.googleapis.com",
  "compute.googleapis.com",
  "iam.googleapis.com",
  "networkmanagement.googleapis.com"
]
