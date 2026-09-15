# ----------------------------------------------------------------------------------------------------------------------
# Storage account
# ----------------------------------------------------------------------------------------------------------------------

output "storage_account_id" {
  description = "Resource ID of the data storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the data storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_dfs_endpoint" {
  description = "Primary dfs endpoint of the data storage account."
  value       = azurerm_storage_account.this.primary_dfs_endpoint
}

output "blob_service_id" {
  description = "Resource ID of the blob service, the target of the blob diagnostic setting."
  value       = "${azurerm_storage_account.this.id}/blobServices/default"
}

output "container_names" {
  description = "Names of the containers in the data storage account, sorted."
  value       = sort(tolist(var.containers))
}

output "container_urls" {
  description = "abfss:// URL of each container, keyed by container name."
  value = {
    for container in var.containers : container => "abfss://${container}@${azurerm_storage_account.this.name}.dfs.core.windows.net/"
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Data Access Connector
# ----------------------------------------------------------------------------------------------------------------------

output "access_connector_id" {
  description = "Resource ID of the data Access Connector."
  value       = azurerm_databricks_access_connector.this.id
}

output "access_connector_principal_id" {
  description = "Principal ID of the data Access Connector's managed identity."
  value       = azurerm_databricks_access_connector.this.identity[0].principal_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoints
# ----------------------------------------------------------------------------------------------------------------------

output "blob_private_endpoint_id" {
  description = "Resource ID of the blob private endpoint."
  value       = azurerm_private_endpoint.blob.id
}

output "dfs_private_endpoint_id" {
  description = "Resource ID of the dfs private endpoint."
  value       = azurerm_private_endpoint.dfs.id
}

output "blob_private_endpoint_ip" {
  description = "Private IP address of the blob private endpoint."
  value       = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
}

output "dfs_private_endpoint_ip" {
  description = "Private IP address of the dfs private endpoint."
  value       = azurerm_private_endpoint.dfs.private_service_connection[0].private_ip_address
}
