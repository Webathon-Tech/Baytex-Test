# ----------------------------------------------------------------------------------------------------------------------
# State backend
# ----------------------------------------------------------------------------------------------------------------------

output "resource_group_name" {
  description = "Resource group of the state storage account."
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "Name of the state storage account."
  value       = azurerm_storage_account.state.name
}

output "storage_account_id" {
  description = "Resource ID of the state storage account."
  value       = azurerm_storage_account.state.id
}

output "container_name" {
  description = "Name of the state container."
  value       = azapi_resource.state_container.name
}

# Printed by the bootstrap workflow so the values can be copied onto the environment's TF_STATE_* GitHub variables.
output "backend_hcl" {
  description = "Backend settings for the platform root, excluding the state key."
  value       = <<-EOT
  resource_group_name  = "${azurerm_resource_group.state.name}"
  storage_account_name = "${azurerm_storage_account.state.name}"
  container_name       = "${azapi_resource.state_container.name}"
  use_azuread_auth     = true
  EOT
}
