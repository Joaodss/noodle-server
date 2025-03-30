variable "actual_subdomain" {
  type        = string
  description = "Subdomain to use for Actual Budget server proxy"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token"
}

variable "actual_server_image_version_tag" {
  type        = string
  description = "Actual Server version tag to use"
}
