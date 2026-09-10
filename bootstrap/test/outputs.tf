output "resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "storage_account_id" {
  value = azurerm_storage_account.state.id
}

output "container_name" {
  value = azapi_resource.state_container.name
}

# Printed by the bootstrap workflow so the values can be copied onto the environment's TF_STATE_* GitHub variables.
output "backend_hcl" {
  value = <<-EOT
  resource_group_name  = "${azurerm_resource_group.state.name}"
  storage_account_name = "${azurerm_storage_account.state.name}"
  container_name       = "${azapi_resource.state_container.name}"
  use_azuread_auth     = true
  EOT
}
