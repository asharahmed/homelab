variable "zone_name" {
  type = string
}

variable "record_name" {
  type = string
}

variable "record_type" {
  type = string
}

variable "record_value" {
  type = string
}

variable "proxied" {
  type    = bool
  default = false
}

variable "comment" {
  type    = string
  default = null
}
