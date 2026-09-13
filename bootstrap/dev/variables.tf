# ----------------------------------------------------------------------------------------------------------------------
# Subscription
# ----------------------------------------------------------------------------------------------------------------------

variable "tenant_id" {
  description = "Microsoft Entra tenant ID."
  type        = string

  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "subscription_id" {
  description = "Azure subscription that holds this environment's Terraform state."
  type        = string

  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "location" {
  description = "Azure region of the resource group and storage account."
  type        = string
  default     = "canadacentral"
}

# ----------------------------------------------------------------------------------------------------------------------
# State storage
# ----------------------------------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource group for the Terraform state account. Must match TF_STATE_RESOURCE_GROUP on the same GitHub Environment."
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique storage account name. Must match TF_STATE_STORAGE_ACCOUNT on the same GitHub Environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "container_name" {
  description = "Blob container holding the state files. Must match TF_STATE_CONTAINER on the same GitHub Environment."
  type        = string
  default     = "tfstate"
}

variable "tags" {
  description = "Tags applied to the resource group and storage account."
  type        = map(string)
  default = {
    Application = "AzureDatabricks"
    ManagedBy   = "Terraform"
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Access
# ----------------------------------------------------------------------------------------------------------------------

variable "state_blob_data_contributor_principal_ids" {
  description = "Object IDs, not application IDs, granted Storage Blob Data Contributor on the state account. Leave empty unless an operator needs direct state access."
  type        = set(string)
  default     = []
}
