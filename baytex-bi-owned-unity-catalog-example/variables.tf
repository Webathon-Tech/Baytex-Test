variable "databricks_account_id" {
  type        = string
  description = "Existing Baytex Azure Databricks account ID."
}

variable "metastore_id" {
  type        = string
  description = "Existing regional Unity Catalog metastore ID."
}

variable "workspace_id" {
  type        = number
  description = "New DEV Databricks workspace ID from the AMTRA platform output."
}

variable "workspace_url" {
  type        = string
  description = "New DEV workspace URL including https://."
}

variable "access_connector_id" {
  type        = string
  description = "AMTRA-created Azure Databricks Access Connector resource ID."
}

variable "storage_account_name" {
  type        = string
  description = "AMTRA-created DEV ADLS Gen2 account name."
}

variable "storage_credential_name" {
  type    = string
  default = "sc_bte_dev"
}

variable "managed_external_location_name" {
  type    = string
  default = "el_bte_dev_managed"
}

variable "external_location_name" {
  type    = string
  default = "el_bte_dev_external"
}

variable "catalog_name" {
  type    = string
  default = "bte_dev"
}

variable "catalog_owner" {
  type        = string
  description = "Existing Databricks account group that owns the DEV catalog."
}

variable "storage_credential_owner" {
  type        = string
  description = "Existing Databricks account group that owns the storage credential."
}

variable "external_location_owner" {
  type        = string
  description = "Existing Databricks account group that owns both external locations."
}

variable "managed_container_name" {
  type    = string
  default = "managed"
}

variable "external_container_name" {
  type    = string
  default = "external"
}

variable "schemas" {
  description = "Optional environment-specific schemas created by Baytex BI."
  type = map(object({
    comment = optional(string)
    owner   = optional(string)
  }))
  default = {}
}

variable "catalog_grants" {
  description = "Catalog-level grants by existing Databricks account group or service principal application ID."
  type        = map(set(string))
  default     = {}
}

variable "schema_grants" {
  description = "Schema-level grants. Outer key is schema name; inner key is principal."
  type        = map(map(set(string)))
  default     = {}
}

variable "external_location_grants" {
  description = "Grants for the general-purpose external location."
  type        = map(set(string))
  default     = {}
}

variable "managed_external_location_grants" {
  description = "Grants for the managed catalog storage external location. Usually restricted to platform/catalog owners."
  type        = map(set(string))
  default     = {}
}

variable "storage_credential_grants" {
  description = "Storage-credential grants by existing Databricks account group or service principal application ID."
  type        = map(set(string))
  default     = {}
}

variable "additional_catalog_workspace_bindings" {
  description = "Additional workspace bindings approved by Baytex BI. The current DEV workspace is bound automatically when the isolated catalog is created."
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
  description = "Additional read-write workspace bindings for both isolated external locations."
  type = map(object({
    workspace_id = number
  }))
  default = {}
}

variable "additional_storage_credential_workspace_bindings" {
  description = "Additional read-write workspace bindings for the isolated storage credential."
  type = map(object({
    workspace_id = number
  }))
  default = {}
}
