variable "tenant_id" {
  description = "Baytex Microsoft Entra tenant ID."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription that will hold the DEV Terraform state."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "canadacentral"
}

variable "resource_group_name" {
  description = "Resource group for Terraform state."
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique storage account name, 3-24 lowercase alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "container_name" {
  description = "Blob container for DEV state."
  type        = string
  default     = "tfstate"
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default = {
    Application = "AzureDatabricks"
    Environment = "Dev"
    ManagedBy   = "Terraform"
    Owner       = "Baytex Infrastructure"
  }
}

variable "state_blob_data_contributor_principal_ids" {
  description = "Object IDs that require Storage Blob Data Contributor on the Terraform state account, such as the GitHub OIDC deployment service principal and approved platform operators."
  type        = set(string)
  default     = []
}
