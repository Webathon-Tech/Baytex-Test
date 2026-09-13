# ----------------------------------------------------------------------------------------------------------------------
# NCC
# ----------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name of the Network Connectivity Configuration."
  type        = string
}

variable "region" {
  description = "Azure region of the NCC. Must match the workspace region."
  type        = string
}

variable "workspace_id" {
  description = "Numeric ID of the Databricks workspace the NCC is bound to."
  type        = number
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoint rule targets
# ----------------------------------------------------------------------------------------------------------------------

variable "storage_account_id" {
  description = "Resource ID of the data storage account that receives the blob and dfs rules."
  type        = string
}

variable "private_link_services" {
  description = "Private Link Service ID and domain names of each on-premises destination, keyed by destination name."
  type = map(object({
    id           = string
    domain_names = list(string)
  }))
}
