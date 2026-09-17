# ----------------------------------------------------------------------------------------------------------------------
# Databricks workspace module
# Creates the Premium Azure Databricks workspace with VNet injection.
# When the default storage firewall is enabled, it also creates the root Access Connector and the blob and dfs private endpoints to the workspace root storage account.
# ----------------------------------------------------------------------------------------------------------------------

locals {
  # Resource ID of the root (DBFS) storage account, which Azure Databricks creates in the managed resource group under the name set on the workspace.
  root_storage_account_id = "${azurerm_databricks_workspace.this.managed_resource_group_id}/providers/Microsoft.Storage/storageAccounts/${var.root_storage_account_name}"
}

# ----------------------------------------------------------------------------------------------------------------------
# Root Access Connector
# ----------------------------------------------------------------------------------------------------------------------

# Managed identity for the workspace root storage account, created only when default_storage_firewall_enabled is true.
# Azure Databricks exempts the attached connector from the managed resource group's deny assignment and grants its roles on the root storage account.
# Terraform assigns no roles on that storage account, because the deny assignment blocks deleting role assignments there, which would prevent the environment from being destroyed.
resource "azurerm_databricks_access_connector" "root" {
  count = var.default_storage_firewall_enabled ? 1 : 0

  name                = var.root_access_connector_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Workspace
# ----------------------------------------------------------------------------------------------------------------------

# Records the default storage firewall setting, so that changing it replaces the workspace.
# A workspace keeps referring to its root Access Connector after the firewall is disabled, and Azure refuses to delete a connector a workspace still refers to.
# Replacing the workspace deletes that reference with it, so disabling the firewall also removes the connector and the private endpoints cleanly.
resource "terraform_data" "default_storage_firewall" {
  input = var.default_storage_firewall_enabled
}

# The resource group is passed as a plain name rather than looked up, so every argument is known at plan time and a tag change updates the workspace in place.
# The name, managed resource group, VNet, subnets, root storage account name, infrastructure encryption and default storage firewall can be set only when the workspace is created; changing any of them replaces it.
resource "azurerm_databricks_workspace" "this" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  sku                               = "premium"
  managed_resource_group_name       = var.managed_resource_group_name
  public_network_access_enabled     = var.public_network_access_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  tags                              = var.tags

  # The provider requires both arguments together, so both are null when the firewall is disabled.
  default_storage_firewall_enabled = var.default_storage_firewall_enabled ? true : null
  access_connector_id              = one(azurerm_databricks_access_connector.root[*].id)

  custom_parameters {
    # Secure cluster connectivity: cluster nodes have no public IP addresses.
    no_public_ip = true

    # VNet injection into the spoke. Databricks calls the host subnet "public" and the container subnet "private".
    virtual_network_id                                   = var.virtual_network_id
    public_subnet_name                                   = var.host_subnet_name
    private_subnet_name                                  = var.container_subnet_name
    public_subnet_network_security_group_association_id  = var.host_nsg_association_id
    private_subnet_network_security_group_association_id = var.container_nsg_association_id

    # Root (DBFS) storage account that Databricks creates in the managed resource group.
    storage_account_name     = var.root_storage_account_name
    storage_account_sku_name = "Standard_GRS"
  }

  # The firewall setting is applied when the workspace is created, so later differences in these two arguments are not sent as an update.
  lifecycle {
    ignore_changes       = [default_storage_firewall_enabled, access_connector_id]
    replace_triggered_by = [terraform_data.default_storage_firewall]
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Root storage private endpoints
# ----------------------------------------------------------------------------------------------------------------------

# When the firewall is enabled, the root storage account accepts no public traffic, so classic compute reaches it through these endpoints in the spoke private endpoint subnet.
# Azure allocates each endpoint's address dynamically; the root_private_endpoint_ips output reports the addresses for the DNS records.
# The endpoints are in the same subscription as the storage account, so their connections are approved automatically.
#
# Private DNS registration uses the same zones as the data storage endpoints.
# When zone IDs are supplied, each endpoint gets a DNS zone group and Azure writes its A record into those Private DNS zones.
# When the list is empty, no zone group is created and DNS records for the endpoint are managed outside Terraform.
resource "azurerm_private_endpoint" "root_blob" {
  count = var.default_storage_firewall_enabled ? 1 : 0

  name                = "pe-${var.root_storage_account_name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.root_storage_account_name}-blob"
    private_connection_resource_id = local.root_storage_account_id
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

resource "azurerm_private_endpoint" "root_dfs" {
  count = var.default_storage_firewall_enabled ? 1 : 0

  name                = "pe-${var.root_storage_account_name}-dfs"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.root_storage_account_name}-dfs"
    private_connection_resource_id = local.root_storage_account_id
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

# ----------------------------------------------------------------------------------------------------------------------
# State addresses
# ----------------------------------------------------------------------------------------------------------------------

# State that holds the connector at the unindexed address is carried over to the indexed one, so the connector of a workspace with the firewall enabled is kept rather than replaced.
moved {
  from = azurerm_databricks_access_connector.root
  to   = azurerm_databricks_access_connector.root[0]
}
