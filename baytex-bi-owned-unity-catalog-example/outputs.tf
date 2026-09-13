# ----------------------------------------------------------------------------------------------------------------------
# Unity Catalog objects
# ----------------------------------------------------------------------------------------------------------------------

output "metastore_assignment_id" {
  description = "ID of the workspace metastore assignment."
  value       = databricks_metastore_assignment.dev.id
}

output "catalog_name" {
  description = "Name of the environment catalog."
  value       = databricks_catalog.dev.name
}

output "storage_credential_name" {
  description = "Name of the storage credential."
  value       = databricks_storage_credential.dev.name
}

output "managed_external_location_name" {
  description = "Name of the managed external location."
  value       = databricks_external_location.managed.name
}

output "external_location_name" {
  description = "Name of the general-purpose external location."
  value       = databricks_external_location.external.name
}

output "schema_names" {
  description = "Names of the schemas created in the catalog."
  value       = keys(databricks_schema.this)
}
