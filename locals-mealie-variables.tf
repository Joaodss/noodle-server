variable "mealie_subdomain" {
  type        = string
  description = "Subdomain to use for Mealie server proxy"
}

variable "mealie_image_version_tag" {
  type        = string
  description = "Mealie version tag to use"
}

variable "mealie_config" {
  type = object({
    timezone = string
  })
  description = "Configuration for Mealie service"
}
