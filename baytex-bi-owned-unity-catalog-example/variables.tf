# ----------------------------------------------------------------------------------------------------------------------
# Platform workspace and storage
# Take these values from the platform's unity_catalog_handoff output.
# ----------------------------------------------------------------------------------------------------------------------

variable "workspace_id" {
  description = "Numeric ID of the platform workspace, from workspace_id in the unity_catalog_handoff platform output."
  type        = number
}

variable "workspace_url" {
  description = "URL of the platform workspace including https://, from workspace_url in the unity_catalog_handoff platform output."
  type        = string
}

variable "external_location_url" {
  description = "abfss:// URL of the platform's external location, from external_location_url in the unity_catalog_handoff platform output. The catalog's managed storage is a folder under it."
  type        = string

  validation {
    condition     = can(regex("^abfss://[a-z0-9-]+@[a-z0-9]+\\.dfs\\.core\\.windows\\.net/?$", var.external_location_url))
    error_message = "external_location_url must be an abfss:// container URL, such as abfss://unity-catalog@stbtedbxdevcnc001.dfs.core.windows.net/."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Catalog
# ----------------------------------------------------------------------------------------------------------------------

variable "catalog_name" {
  description = "Name of the environment catalog."
  type        = string
  default     = "bte_dev"
}

variable "catalog_owner" {
  description = "Existing Databricks account group that owns the catalog."
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
