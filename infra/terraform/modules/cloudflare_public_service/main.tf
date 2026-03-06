terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

data "cloudflare_zones" "selected" {
  name   = var.zone_name
  status = "active"
}

locals {
  zone_id = data.cloudflare_zones.selected.result[0].id
}

resource "cloudflare_dns_record" "this" {
  zone_id = local.zone_id
  name    = var.record_name
  type    = var.record_type
  content = var.record_value
  ttl     = 1
  proxied = var.proxied
  comment = var.comment
}
