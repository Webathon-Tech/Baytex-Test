output "metastore_assignment_id" {
  value = databricks_metastore_assignment.dev.id
}

output "catalog_name" {
  value = databricks_catalog.dev.name
}

output "storage_credential_name" {
  value = databricks_storage_credential.dev.name
}

output "managed_external_location_name" {
  value = databricks_external_location.managed.name
}

output "external_location_name" {
  value = databricks_external_location.external.name
}

output "schema_names" {
  value = keys(databricks_schema.this)
}
