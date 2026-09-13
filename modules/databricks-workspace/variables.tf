# ----------------------------------------------------------------------------------------------------------------------
# General
# ----------------------------------------------------------------------------------------------------------------------

variable "location" {
  description = "Azure region for the workspace and the root Access Connector."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the workspace and the root Access Connector."
  type        = string
}

variable "tags" {
  description = "Tags applied to the workspace and the root Access Connector."
  type        = map(string)
}

# ----------------------------------------------------------------------------------------------------------------------
# Workspace
# ----------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name of the Databricks workspace."
  type        = string
}

variable "managed_resource_group_name" {
  description = "Name of the managed resource group Databricks creates for the workspace."
  type        = string
}

variable "root_storage_account_name" {
  description = "Globally unique name of the root (DBFS) storage account Databricks creates in the managed resource group."
  type        = string
}

variable "public_network_access_enabled" {
  description = "Whether the workspace front end accepts connections from public networks."
  type        = bool
}

variable "infrastructure_encryption_enabled" {
  description = "Enable a second layer of encryption on the root storage account. Set when the workspace is created."
  type        = bool
}

variable "default_storage_firewall_enabled" {
  description = "Firewall the root storage account. Creates the root Access Connector and attaches it to the workspace."
  type        = bool
}

variable "root_access_connector_name" {
  description = "Name of the root Access Connector, created only when default_storage_firewall_enabled is true."
  type        = string
}

# ----------------------------------------------------------------------------------------------------------------------
# VNet injection
# ----------------------------------------------------------------------------------------------------------------------

variable "virtual_network_id" {
  description = "Resource ID of the spoke VNet the workspace is injected into."
  type        = string
}

variable "host_subnet_name" {
  description = "Name of the Databricks host (public) subnet."
  type        = string
}

variable "container_subnet_name" {
  description = "Name of the Databricks container (private) subnet."
  type        = string
}

variable "host_nsg_association_id" {
  description = "ID of the NSG association on the host subnet."
  type        = string
}

variable "container_nsg_association_id" {
  description = "ID of the NSG association on the container subnet."
  type        = string
}
