output "service_metadata" {
  description = "Service metadata loaded from infra data files."
  value       = try(local.service_index, {})
}

output "network_metadata" {
  description = "Network/security zone metadata loaded from infra data files."
  value       = try(local.networks, {})
}
