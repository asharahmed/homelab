locals {
  rendered_grants = {
    tailnet = var.tailnet
    grants  = var.grants
  }
}

output "planned_policy" {
  value = local.rendered_grants
}
