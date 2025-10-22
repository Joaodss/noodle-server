variable "actual_auto_sync_config" {
  type = object({
    server_url      = string
    server_password = string
    sync_ids        = string
    file_passwords  = string
    cron_schedule   = string
    log_level       = string
    run_on_start    = bool
  })
  description = "Configuration for Actual Auto Sync service"
}

variable "actual_auto_sync_image_version_tag" {
  type        = string
  description = "Actual Auto Sync version tag to use"
}
