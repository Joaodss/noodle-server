variable "gcp_ssh_allowed_source_ranges" {
  type        = list(string)
  description = "Extra CIDR ranges allowed to SSH besides Google IAP. Set from the SSH_ALLOWED_RANGES secret, not committed."
  default     = []
}
