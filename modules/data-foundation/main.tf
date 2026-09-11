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

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01"
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

# The same four roles Databricks grants the connector it attaches to a workspace's own storage account. Storage Blob
# Data Contributor is what a Unity Catalog storage credential needs; the other three let Databricks set up file events
# (a storage queue and an Event Grid subscription) for Auto Loader.
resource "azurerm_role_assignment" "access_connector_storage" {
  for_each = toset([
    "Storage Blob Data Contributor",
    "Storage Account Contributor",
    "Storage Queue Data Contributor",
    "EventGrid EventSubscription Contributor",
  ])

  scope                            = azurerm_storage_account.this.id
  role_definition_name             = each.value
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
