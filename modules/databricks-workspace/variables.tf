variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name" { type = string }
variable "managed_resource_group_name" { type = string }
variable "root_storage_account_name" { type = string }
variable "root_access_connector_name" { type = string }
variable "virtual_network_id" { type = string }
variable "host_subnet_name" { type = string }
variable "container_subnet_name" { type = string }
variable "host_nsg_association_id" { type = string }
variable "container_nsg_association_id" { type = string }
variable "public_network_access_enabled" { type = bool }
variable "infrastructure_encryption_enabled" { type = bool }

variable "default_storage_firewall_enabled" {
  type        = bool
  description = "Firewall the Databricks-managed root storage; attaches the root Access Connector to the workspace."
}

variable "tags" { type = map(string) }
