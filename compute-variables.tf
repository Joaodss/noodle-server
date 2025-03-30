variable "gcp_vm_image_family" {
  type        = string
  description = "Family of image to use with VM creation"
}

variable "gcp_vm_image_project" {
  type        = string
  description = "Project to which the image belongs."
}

variable "gcp_vm_size" {
  type        = string
  description = "VM instance type."
}

variable "gcp_container_host_network_tags" {
  type        = list(string)
  description = "List of network tags to add for firewall rules"
}
