# ----------------------------------------------------------------------------------------------------------------------
# Databricks account and workspace
# Take these values from the platform's unity_catalog_handoff output.
# ----------------------------------------------------------------------------------------------------------------------

variable "databricks_account_id" {
  description = "Existing Baytex Azure Databricks account ID."
  type        = string
}

variable "metastore_id" {
  description = "Existing regional Unity Catalog metastore ID."
  type        = string
}

variable "workspace_id" {
  description = "Numeric ID of the platform workspace, from the databricks_workspace_id platform output."
  type        = number
}

variable "workspace_url" {
  description = "URL of the platform workspace including https://, from the databricks_workspace_url platform output."
  type        = string
}

# ----------------------------------------------------------------------------------------------------------------------
# Platform storage
# ----------------------------------------------------------------------------------------------------------------------

variable "access_connector_id" {
  description = "Resource ID of the data Access Connector, from the data_access_connector_id platform output."
  type        = string
}

variable "storage_account_name" {
  description = "Name of the ADLS Gen2 data storage account, from the data_storage_account_name platform output."
  type        = string
}

variable "managed_container_name" {
  description = "Container that backs the managed external location."
  type        = string
  default     = "managed"
}

variable "external_container_name" {
  description = "Container that backs the general-purpose external location."
  type        = string
  default     = "external"
}

# ----------------------------------------------------------------------------------------------------------------------
# Unity Catalog object names
# ----------------------------------------------------------------------------------------------------------------------

variable "storage_credential_name" {
  description = "Name of the storage credential."
  type        = string
  default     = "sc_bte_dev"
}

variable "managed_external_location_name" {
  description = "Name of the external location for managed catalog storage."
  type        = string
  default     = "el_bte_dev_managed"
}

variable "external_location_name" {
  description = "Name of the general-purpose external location."
  type        = string
  default     = "el_bte_dev_external"
}

variable "catalog_name" {
  description = "Name of the environment catalog."
  type        = string
  default     = "bte_dev"
}

# ----------------------------------------------------------------------------------------------------------------------
# Ownership
# ----------------------------------------------------------------------------------------------------------------------

variable "catalog_owner" {
  description = "Existing Databricks account group that owns the catalog."
  type        = string
}

variable "storage_credential_owner" {
  description = "Existing Databricks account group that owns the storage credential."
  type        = string
}

variable "external_location_owner" {
  description = "Existing Databricks account group that owns both external locations."
  type        = string
}

# ----------------------------------------------------------------------------------------------------------------------
# Schemas
# ----------------------------------------------------------------------------------------------------------------------

variable "schemas" {
  description = "Schemas created in the catalog, keyed by schema name. A schema without a comment gets a default comment, and a schema without an owner is owned by catalog_owner."
  type = map(object({
    comment = optional(string)
    owner   = optional(string)
  }))
  default = {}
}

# ----------------------------------------------------------------------------------------------------------------------
# Grants
# ----------------------------------------------------------------------------------------------------------------------

variable "catalog_grants" {
  description = "Catalog privileges, keyed by existing account group or service principal application ID."
  type        = map(set(string))
  default     = {}
}

variable "schema_grants" {
  description = "Schema privileges. The outer key is the schema name and the inner key is the principal."
  type        = map(map(set(string)))
  default     = {}
}

variable "managed_external_location_grants" {
  description = "Privileges on the managed external location, usually limited to platform or catalog owners."
  type        = map(set(string))
  default     = {}
}

variable "external_location_grants" {
  description = "Privileges on the general-purpose external location, keyed by principal."
  type        = map(set(string))
  default     = {}
}

variable "storage_credential_grants" {
  description = "Storage credential privileges, keyed by existing account group or service principal application ID."
  type        = map(set(string))
  default     = {}
}

# ----------------------------------------------------------------------------------------------------------------------
# Additional workspace bindings
# ----------------------------------------------------------------------------------------------------------------------

variable "additional_catalog_workspace_bindings" {
  description = "Other workspaces approved by Baytex BI to use the catalog. The current workspace is always bound."
  type = map(object({
    workspace_id = number
    binding_type = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for value in values(var.additional_catalog_workspace_bindings) :
      contains(["BINDING_TYPE_READ_ONLY", "BINDING_TYPE_READ_WRITE"], value.binding_type)
    ])
    error_message = "Catalog binding_type must be BINDING_TYPE_READ_ONLY or BINDING_TYPE_READ_WRITE."
  }
}

variable "additional_external_location_workspace_bindings" {
  description = "Other workspaces bound read-write to both external locations."
  type = map(object({
    workspace_id = number
  }))
  default = {}
}

variable "additional_storage_credential_workspace_bindings" {
  description = "Other workspaces bound read-write to the storage credential."
  type = map(object({
    workspace_id = number
  }))
  default = {}
}
