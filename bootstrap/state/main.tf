resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                          = var.storage_account_name
  resource_group_name           = azurerm_resource_group.state.name
  location                      = azurerm_resource_group.state.location
  account_tier                  = "Standard"
  account_replication_type      = "GRS"
  account_kind                  = "StorageV2"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = true
  # Entra-only. No shared account key exists to be leaked or rotated, and every
  # path to this account authenticates as the service principal through its
  # Storage Blob Data Contributor role: the Terraform backend with
  # use_azuread_auth=true, the az CLI probes with --auth-mode login, and the
  # provider itself with storage_use_azuread (set in versions.tf).
  #
  # storage_use_azuread in versions.tf is what makes this possible. Without it
  # the provider calls ListKeys to build its data-plane client and fails with
  # "403 Key based authentication is not permitted on this storage account".
  # Do not remove one without the other.
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  tags                             = var.tags

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

resource "azapi_resource" "state_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = var.container_name
  parent_id = "${azurerm_storage_account.state.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_role_assignment" "state_blob_data_contributor" {
  for_each = var.state_blob_data_contributor_principal_ids

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
