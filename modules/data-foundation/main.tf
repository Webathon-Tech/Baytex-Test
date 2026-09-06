resource "azurerm_storage_account" "this" {
  name                              = var.storage_account_name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  is_hns_enabled                    = true
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  tags                              = var.tags

  blob_properties {
    # Blob versioning and change feed are NOT supported on accounts with a
    # hierarchical namespace, which ADLS Gen2 requires (is_hns_enabled above).
    # Setting either to true makes the account impossible to create:
    #   "`versioning_enabled` can't be true when `is_hns_enabled` is true"
    # Soft delete for blobs and containers IS supported with HNS, so data
    # protection comes from the two retention policies below.
    versioning_enabled  = false
    change_feed_enabled = false

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azapi_resource" "container" {
  for_each = var.containers

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = each.value
  parent_id = "${azurerm_storage_account.this.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_databricks_access_connector" "this" {
  name                = var.access_connector_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "access_connector_storage" {
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_databricks_access_connector.this.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.storage_account_name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.blob_private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "pdzg-blob"
      private_dns_zone_ids = var.blob_private_dns_zone_ids
    }
  }
}

resource "azurerm_private_endpoint" "dfs" {
  name                = "pe-${var.storage_account_name}-dfs"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.storage_account_name}-dfs"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.dfs_private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "pdzg-dfs"
      private_dns_zone_ids = var.dfs_private_dns_zone_ids
    }
  }
}
