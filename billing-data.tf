data "google_billing_account" "billing_account" {
  display_name = var.gcp_billing_account_name
}
