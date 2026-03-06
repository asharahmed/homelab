variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_zone_name" {
  type    = string
  default = "aahmed.ca"
}

variable "cloudflare_account_id" {
  type    = string
  default = ""
}

variable "tailscale_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "tailscale_tailnet" {
  type    = string
  default = ""
}

variable "enable_cloudflare" {
  type    = bool
  default = false
}

variable "enable_tailscale" {
  type    = bool
  default = false
}
