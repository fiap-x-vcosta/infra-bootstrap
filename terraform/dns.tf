resource "google_dns_managed_zone" "public" {
  name        = var.dns_managed_zone_name
  dns_name    = var.dns_name
  description = "Zona pública do domínio da demo."
  visibility  = "public"

  dnssec_config {
    state = "on"
  }

  depends_on = [google_project_service.services]
}
