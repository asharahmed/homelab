output "record_id" {
  value = cloudflare_dns_record.this.id
}

output "record_name" {
  value = cloudflare_dns_record.this.name
}

output "zone_id" {
  value = cloudflare_dns_record.this.zone_id
}
