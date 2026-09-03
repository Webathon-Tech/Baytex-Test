output "storage_account_id" { value = azurerm_storage_account.this.id }
output "storage_account_name" { value = azurerm_storage_account.this.name }
output "storage_account_dfs_endpoint" { value = azurerm_storage_account.this.primary_dfs_endpoint }
output "access_connector_id" { value = azurerm_databricks_access_connector.this.id }
output "access_connector_principal_id" { value = azurerm_databricks_access_connector.this.identity[0].principal_id }
output "blob_private_endpoint_id" { value = azurerm_private_endpoint.blob.id }
output "dfs_private_endpoint_id" { value = azurerm_private_endpoint.dfs.id }
output "container_names" { value = sort(tolist(var.containers)) }
output "container_urls" {
  value = {
    for container in var.containers : container => "abfss://${container}@${azurerm_storage_account.this.name}.dfs.core.windows.net/"
  }
}

output "blob_service_id" { value = "${azurerm_storage_account.this.id}/blobServices/default" }
