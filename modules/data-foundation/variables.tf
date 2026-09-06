variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "storage_account_name" { type = string }
variable "access_connector_name" { type = string }
variable "private_endpoint_subnet_id" { type = string }

variable "containers" {
  description = "Containers created through the ARM management plane."
  type        = set(string)
  default     = ["managed", "external", "landing", "checkpoints"]
}

variable "blob_private_dns_zone_ids" {
  type    = set(string)
  default = []
}

variable "dfs_private_dns_zone_ids" {
  type    = set(string)
  default = []
}

variable "tags" { type = map(string) }
