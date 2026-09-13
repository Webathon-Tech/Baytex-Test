# ----------------------------------------------------------------------------------------------------------------------
# State backend root
# Creates the storage account and container that hold this environment's platform Terraform state.
# The dev, test and prod bootstrap roots hold identical .tf files, and each environment's values come from its terraform.tfvars.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# Resource group
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ----------------------------------------------------------------------------------------------------------------------
# State storage account
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_storage_account" "state" {
  name                             = var.storage_account_name
  resource_group_name              = azurerm_resource_group.state.name
  location                         = azurerm_resource_group.state.location
  account_tier                     = "Standard"
  account_replication_type         = "GRS"
  account_kind                     = "StorageV2"
  min_tls_version                  = "TLS1_2"
  public_network_access            = "Enabled"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  tags                             = var.tags

  # Microsoft Entra ID authentication only.
  # Every caller authenticates with a Storage Blob Data role, so there is no account key to leak or rotate.
  # This requires storage_use_azuread = true in versions.tf; the two settings must change together.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  # Versioning and 30-day soft delete let a corrupted or deleted state file be recovered.
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

# Created through the Azure Resource Manager API rather than azurerm_storage_container, so no account key or data-plane access is needed.
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

# ----------------------------------------------------------------------------------------------------------------------
# Optional operator access
# ----------------------------------------------------------------------------------------------------------------------

# The deployment service principal already holds Storage Blob Data Contributor at subscription scope.
# These assignments are for anyone else who needs to read state directly, such as an operator investigating a failed run.
resource "azurerm_role_assignment" "state_blob_data_contributor" {
  for_each = var.state_blob_data_contributor_principal_ids

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
