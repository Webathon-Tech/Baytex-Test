# ----------------------------------------------------------------------------------------------------------------------
# General
# ----------------------------------------------------------------------------------------------------------------------

variable "location" {
  description = "Azure region for every resource in this module."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the data storage account, its private endpoints and the data Access Connector."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource that supports them."
  type        = map(string)
}

# ----------------------------------------------------------------------------------------------------------------------
# Storage account and Access Connector
# ----------------------------------------------------------------------------------------------------------------------

variable "storage_account_name" {
  description = "Globally unique name of the ADLS Gen2 data storage account."
  type        = string
}

variable "containers" {
  description = "Containers created in the data storage account."
  type        = set(string)
  default     = ["managed", "external", "landing", "checkpoints"]
}

variable "access_connector_name" {
  description = "Name of the data Access Connector."
  type        = string
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoints and DNS
# ----------------------------------------------------------------------------------------------------------------------

variable "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet the blob and dfs private endpoints are placed in."
  type        = string
}

variable "blob_private_endpoint_ip" {
  description = "Static private IP of the blob private endpoint, inside the private endpoint subnet. Null lets Azure allocate one dynamically."
  type        = string
  default     = null
}

variable "dfs_private_endpoint_ip" {
  description = "Static private IP of the dfs private endpoint, inside the private endpoint subnet. Null lets Azure allocate one dynamically."
  type        = string
  default     = null
}

variable "blob_private_dns_zone_ids" {
  description = "Resource IDs of privatelink.blob.core.windows.net zones the blob private endpoint registers in. Empty creates no DNS zone group."
  type        = set(string)
  default     = []
}

variable "dfs_private_dns_zone_ids" {
  description = "Resource IDs of privatelink.dfs.core.windows.net zones the dfs private endpoint registers in. Empty creates no DNS zone group."
  type        = set(string)
  default     = []
}

# ----------------------------------------------------------------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------------------------------------------------------------

variable "enable_alerts" {
  description = "Create the data storage account availability alert."
  type        = bool
  default     = false
}

variable "alert_action_group_ids" {
  description = "Action groups the alert notifies. An empty list raises the alert in Azure Monitor without notifying anyone."
  type        = list(string)
  default     = []
}
