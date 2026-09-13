# ----------------------------------------------------------------------------------------------------------------------
# Data foundation module
# Creates the ADLS Gen2 data storage account and its containers, the data Access Connector with its storage roles, and the blob and dfs private endpoints.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# Data storage account
# ----------------------------------------------------------------------------------------------------------------------

# Public network access is disabled, so the account is reached through its private endpoints in the spoke and through the private endpoint rules of the Databricks NCC.
# Shared key access is disabled, so every caller authenticates with Microsoft Entra ID.
resource "azurerm_storage_account" "this" {
  name                              = var.storage_account_name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  is_hns_enabled                    = true
  min_tls_version                   = "TLS1_2"
  public_network_access             = "Disabled"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  tags                              = var.tags

  # Deleted blobs and containers can be restored for 30 days.
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

# Containers are created through the Azure Resource Manager API, so Terraform needs no data-plane access to the storage account.
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

# ----------------------------------------------------------------------------------------------------------------------
# Data Access Connector
# ----------------------------------------------------------------------------------------------------------------------

# Managed identity that Baytex BI uses for the Unity Catalog storage credential on this storage account.
resource "azurerm_databricks_access_connector" "this" {
  name                = var.access_connector_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# The same four roles Databricks grants the connector it attaches to a workspace's own storage account.
# Storage Blob Data Contributor is what a Unity Catalog storage credential needs.
# The other three let Databricks set up file events, a storage queue and an Event Grid subscription, for Auto Loader.
# Each key is the role name and each value is the description shown on the role assignment in Azure.
resource "azurerm_role_assignment" "access_connector_storage" {
  for_each = {
    "Storage Blob Data Contributor"           = "Lets Access Connector ${var.access_connector_name} read and write data in ${var.storage_account_name} for the Unity Catalog storage credential."
    "Storage Account Contributor"             = "Lets Access Connector ${var.access_connector_name} configure file events on ${var.storage_account_name} for Databricks Auto Loader."
    "Storage Queue Data Contributor"          = "Lets Access Connector ${var.access_connector_name} create and read the file event queues on ${var.storage_account_name} for Databricks Auto Loader."
    "EventGrid EventSubscription Contributor" = "Lets Access Connector ${var.access_connector_name} create the Event Grid subscriptions on ${var.storage_account_name} for Databricks Auto Loader."
  }

  scope                            = azurerm_storage_account.this.id
  role_definition_name             = each.key
  description                      = each.value
  principal_id                     = azurerm_databricks_access_connector.this.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoints
# ----------------------------------------------------------------------------------------------------------------------

# One private endpoint per storage sub-resource, placed in the spoke private endpoint subnet.
# The endpoints are in the same subscription as the storage account, so their connections are approved automatically.
#
# Private DNS registration is optional.
# When zone IDs are supplied, each endpoint gets a DNS zone group and Azure writes its A record into those Private DNS zones.
# The zones can be in another subscription, such as the hub, as long as the deployment identity holds Private DNS Zone Contributor on each zone.
# When the list is empty, no zone group is created and DNS records for the endpoint are managed outside Terraform.
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
