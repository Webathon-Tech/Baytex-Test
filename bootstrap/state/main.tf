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
  # Must stay true. The blob_properties block below is a DATA-PLANE setting, and
  # the azurerm provider in this root reaches the blob endpoint with a shared
  # account key. Setting this to false makes the account impossible to manage:
  #   Error: encoding Storage Account (...): executing request: unexpected
  #   status 403 (403 Key based authentication is not permitted on this storage
  #   account.) with KeyBasedAuthenticationNotPermitted
  #
  # The environment roots avoid this by setting storage_use_azuread = true on
  # their azurerm provider, which routes data-plane calls through Entra. This
  # root does not set it, so the key path is the only one available here.
  #
  # Access to the state itself is Entra-only regardless: the Terraform backend
  # uses use_azuread_auth=true and the az CLI probes use --auth-mode login, both
  # as the service principal via its Storage Blob Data Contributor role. No
  # pipeline ever reads or passes the account key.
  shared_access_key_enabled        = true
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
