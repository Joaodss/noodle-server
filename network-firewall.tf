locals {
  cloudflare_ips = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22"
  ]
}

resource "google_compute_firewall" "allow_http_https" {
  name        = "allow-http-https"
  description = "Allows HTTP/HTTPS traffic from Cloudflare"
  network     = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  direction     = "INGRESS"
  target_tags   = ["http-server", "https-server"]
  source_ranges = local.cloudflare_ips
  priority      = "1000"
}

resource "google_compute_firewall" "allow_https_udp" {
  name        = "allow-https-udp"
  description = "Allows QUIC/HTTP3 traffic from Cloudflare"
  network     = google_compute_network.vpc_network.name

  allow {
    protocol = "udp"
    ports    = ["443"]
  }

  direction     = "INGRESS"
  target_tags   = ["https-server-udp"]
  source_ranges = local.cloudflare_ips
  priority      = "1000"
}

resource "google_compute_firewall" "allow_ssh_proxy" {
  name        = "allow-ssh-proxy"
  description = "Allows SSH from Google's Identity Aware Proxy (IAP)"
  network     = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  direction     = "INGRESS"
  target_tags   = ["allow-ssh-proxy"]
  source_ranges = ["35.235.240.0/20"]
  priority      = "1000"
}
