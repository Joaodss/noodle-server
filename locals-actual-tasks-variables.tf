variable "actual_tasks_image_version_tag" {
  type        = string
  description = "Actual Tasks version tag to use"
}
variable "actual_tasks_config" {
  type = object({
    cron_expression = string
    actual = object({
      server_url      = string
      server_password = string
      sync_id         = string
      file_password   = string
    })
    features = object({
      payee_rename = object({
        is_enabled  = bool
        regex_match = string
      })
      interest_calculation = object({
        is_enabled         = bool
        rate               = string
        payee_id           = string
        main_account_id    = string
        mortage_account_id = string
      })
      ghostfolio = object({
        is_enabled     = bool
        account        = string
        actual_account = string
        payee_name     = string
        server_url     = string
        token          = string
      })
      hold_income_for_next_month = object({
        is_enabled = bool
      })
      bank_sync = object({
        is_enabled = bool
      })
    })
  })
  description = "Configuration for Actual Tasks service"
}
