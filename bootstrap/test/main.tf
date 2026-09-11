resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                             = var.storage_account_name
  resource_group_name              = azurerm_resource_group.state.name
  location                         = azurerm_resource_group.state.location
  account_tier                     = "Standard"
  account_replication_type         = "GRS"
  account_kind                     = "StorageV2"
  min_tls_version                  = "TLS1_2"
  public_network_access_enabled    = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  tags                             = var.tags

  # Entra-only. Every path to this account authenticates as the service principal through its Storage Blob Data
  # Contributor role, so there is no account key to leak or rotate. This works only because versions.tf sets
  # storage_use_azuread = true; removing one without the other breaks the root.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  # Versioning and both soft-delete windows exist so a corrupted or accidentally deleted state file can be recovered.
  # This account holds the only record of what the platform consists of.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

# Created through azapi rather than azurerm_storage_container, which reaches the blob data plane and would need the
# account key this account does not have.
resource "azapi_resource" "state_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01"
  name      = var.container_name
  parent_id = "${azurerm_storage_account.state.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

# Optional. The deployment service principal already holds this role at subscription scope; this is for anyone else who
# needs to read state directly, such as a platform operator investigating a failed run.
resource "azurerm_role_assignment" "state_blob_data_contributor" {
  for_each = var.state_blob_data_contributor_principal_ids

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
