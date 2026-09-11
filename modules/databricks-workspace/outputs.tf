output "id" { value = azurerm_databricks_workspace.this.id }
output "workspace_id" { value = azurerm_databricks_workspace.this.workspace_id }
output "workspace_url" { value = azurerm_databricks_workspace.this.workspace_url }
output "managed_resource_group_id" { value = azurerm_databricks_workspace.this.managed_resource_group_id }
output "root_access_connector_id" { value = azurerm_databricks_access_connector.root.id }
output "root_access_connector_principal_id" {
  value = azurerm_databricks_access_connector.root.identity[0].principal_id
}
