variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token for Terraform-managed DNS resources."
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_name" {
  type        = string
  description = "Primary Cloudflare zone to manage."
  default     = "aahmed.ca"
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID used for metadata and future account-level resources."
  default     = ""
}

variable "tailscale_api_key" {
  type        = string
  description = "Tailscale API key used for policy/grants automation."
  sensitive   = true
  default     = ""
}

variable "tailscale_tailnet" {
  type        = string
  description = "Tailnet name for Tailscale provider operations."
  default     = ""
}

variable "enable_cloudflare" {
  type        = bool
  description = "Whether to manage Cloudflare resources from this stack."
  default     = false
}

variable "enable_tailscale" {
  type        = bool
  description = "Whether to manage Tailscale resources from this stack."
  default     = false
}
