# ----------------------------------------------------------------------------------------------------------------------
# Unity Catalog objects
# ----------------------------------------------------------------------------------------------------------------------

output "catalog_name" {
  description = "Name of the environment catalog."
  value       = databricks_catalog.dev.name
}

output "catalog_storage_root" {
  description = "Managed storage location of the catalog, under the platform's external location."
  value       = databricks_catalog.dev.storage_root
}

output "schema_names" {
  description = "Names of the schemas created in the catalog."
  value       = keys(databricks_schema.this)
}
