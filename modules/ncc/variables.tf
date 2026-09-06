variable "name" { type = string }
variable "region" { type = string }
variable "workspace_id" { type = number }
variable "storage_account_id" { type = string }

variable "private_link_services" {
  type = map(object({
    id           = string
    domain_names = list(string)
  }))
}
