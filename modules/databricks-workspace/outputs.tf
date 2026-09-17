# ----------------------------------------------------------------------------------------------------------------------
# Workspace
# ----------------------------------------------------------------------------------------------------------------------

output "id" {
  description = "Azure resource ID of the workspace."
  value       = azurerm_databricks_workspace.this.id
}

output "workspace_id" {
  description = "Numeric Databricks workspace ID."
  value       = azurerm_databricks_workspace.this.workspace_id
}

output "workspace_url" {
  description = "Workspace host name, without the https:// scheme."
  value       = azurerm_databricks_workspace.this.workspace_url
}

output "managed_resource_group_id" {
  description = "Resource ID of the managed resource group."
  value       = azurerm_databricks_workspace.this.managed_resource_group_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Default storage firewall
# ----------------------------------------------------------------------------------------------------------------------

output "root_access_connector_id" {
  description = "Resource ID of the root Access Connector, or null when the default storage firewall is disabled."
  value       = one(azurerm_databricks_access_connector.root[*].id)
}

output "root_access_connector_principal_id" {
  description = "Principal ID of the root Access Connector's managed identity, or null when the default storage firewall is disabled."
  value       = one(azurerm_databricks_access_connector.root[*].identity[0].principal_id)
}

output "root_private_endpoint_ips" {
  description = "Private IP addresses of the root storage blob and dfs private endpoints, or null when the default storage firewall is disabled."
  value = var.default_storage_firewall_enabled ? {
    blob = azurerm_private_endpoint.root_blob[0].private_service_connection[0].private_ip_address
    dfs  = azurerm_private_endpoint.root_dfs[0].private_service_connection[0].private_ip_address
  } : null
}
