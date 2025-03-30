variable "gcp_project" {
  type        = string
  description = "Name of the project created."
}

variable "gcp_billing_project" {
  type        = string
  description = "Name of the billing project created. Usually equal to the project name."
}

variable "gcp_project_region" {
  type        = string
  description = "Region to deploy resources."
  default     = "us-central1"
}

variable "gcp_project_zone" {
  type        = string
  description = "Zone to deploy resources."
  default     = "us-central1-c"
}

variable "access_credentials" {
  type        = string
  description = "Path to the service account key file."
}
