variable "gcp_ssh_allowed_cidrs" {
  type        = string
  description = "Comma-separated IPv4 CIDRs allowed to SSH besides Google IAP, e.g. \"1.2.3.4/32\". Set from the SSH_ALLOWED_RANGES secret, not committed."
  default     = ""

  validation {
    condition = alltrue([
      for c in split(",", var.gcp_ssh_allowed_cidrs) :
      trim(c, "\" ") == "" || (can(cidrhost(trim(c, "\" "), 0)) && !endswith(trim(c, "\" "), "/0"))
    ])
    error_message = "gcp_ssh_allowed_cidrs must be comma-separated IPv4 CIDRs and must not contain /0."
  }
}
