# ----------------------------------------------------------------------------------------------------------------------
# General
# ----------------------------------------------------------------------------------------------------------------------

variable "location" {
  description = "Azure region for the workspace, the root Access Connector and the root storage private endpoints."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the workspace, the root Access Connector and the root storage private endpoints."
  type        = string
}

variable "tags" {
  description = "Tags applied to the workspace, the root Access Connector and the root storage private endpoints."
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
  description = "Firewall the root storage account. True creates the root Access Connector, attaches it to the workspace and creates the root storage private endpoints. Set when the workspace is created; changing it replaces the workspace."
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

# ----------------------------------------------------------------------------------------------------------------------
# Root storage private endpoints
# ----------------------------------------------------------------------------------------------------------------------

variable "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet the root storage blob and dfs private endpoints are placed in when the default storage firewall is enabled."
  type        = string
}

variable "blob_private_dns_zone_ids" {
  description = "Resource IDs of privatelink.blob.core.windows.net zones the root storage blob private endpoint registers in. Empty creates no DNS zone group."
  type        = set(string)
  default     = []
}

variable "dfs_private_dns_zone_ids" {
  description = "Resource IDs of privatelink.dfs.core.windows.net zones the root storage dfs private endpoint registers in. Empty creates no DNS zone group."
  type        = set(string)
  default     = []
}
