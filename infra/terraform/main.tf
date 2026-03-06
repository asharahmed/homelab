locals {
  services = yamldecode(file("${path.module}/data/services.yaml")).services
  domains  = yamldecode(file("${path.module}/data/domains.yaml")).domains
  networks = yamldecode(file("${path.module}/data/networks.yaml"))

  service_index = {
    for service in local.services :
    service.name => service
  }

  public_dns_records = {
    for domain in local.domains :
    domain.name => domain
    if try(domain.managed_by_terraform, false)
  }
}

module "cloudflare_public_service" {
  for_each = var.enable_cloudflare ? local.public_dns_records : {}

  source = "./modules/cloudflare_public_service"

  zone_name    = var.cloudflare_zone_name
  record_name  = each.value.name
  record_type  = try(each.value.type, "A")
  record_value = each.value.value
  proxied      = try(each.value.proxied, false)
  comment      = try(each.value.comment, null)
}

module "tailscale_policy" {
  count = var.enable_tailscale ? 1 : 0

  source = "./modules/tailscale_policy"

  tailnet = var.tailscale_tailnet
  grants  = try(local.networks.tailscale_grants, [])
}
