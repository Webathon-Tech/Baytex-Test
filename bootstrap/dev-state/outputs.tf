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

output "backend_hcl" {
  value = <<-EOT
  resource_group_name  = "${azurerm_resource_group.state.name}"
  storage_account_name = "${azurerm_storage_account.state.name}"
  container_name       = "${azapi_resource.state_container.name}"
  key                  = "dev/platform.tfstate"
  use_azuread_auth     = true
  EOT
}
