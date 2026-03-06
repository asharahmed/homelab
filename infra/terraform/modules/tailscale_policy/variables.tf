variable "tailnet" {
  type = string
}

variable "grants" {
  type = list(object({
    src  = list(string)
    dst  = list(string)
    note = optional(string)
  }))
  default = []
}
