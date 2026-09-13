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
# Root Access Connector
# ----------------------------------------------------------------------------------------------------------------------

output "root_access_connector_id" {
  description = "Resource ID of the root Access Connector, or null when the default storage firewall is off."
  value       = one(azurerm_databricks_access_connector.root[*].id)
}

output "root_access_connector_principal_id" {
  description = "Principal ID of the root Access Connector's managed identity, or null when the default storage firewall is off."
  value       = one(azurerm_databricks_access_connector.root[*].identity[0].principal_id)
}
