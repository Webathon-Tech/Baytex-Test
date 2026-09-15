# ----------------------------------------------------------------------------------------------------------------------
# Databricks workspace module
# Creates the Premium Azure Databricks workspace with VNet injection, and the root Access Connector when the default storage firewall is enabled.
# ----------------------------------------------------------------------------------------------------------------------

locals {
  # The provider requires default_storage_firewall_enabled and access_connector_id to be set together, so both are always sent.
  # Sending the firewall setting on every apply is what lets it be switched off again: Azure keeps the workspace's current value for a field that is left out.
  firewall_enabled    = var.default_storage_firewall_enabled
  access_connector_id = azurerm_databricks_access_connector.root.id
}

# ----------------------------------------------------------------------------------------------------------------------
# Root Access Connector
# ----------------------------------------------------------------------------------------------------------------------

# Managed identity for the workspace root (DBFS) storage account, attached to the workspace only when default_storage_firewall_enabled is true.
# Once it is attached, Databricks exempts it from the managed resource group's deny assignment and grants its roles on the root storage account.
# Terraform assigns no roles on that storage account, because the deny assignment blocks deleting role assignments there, which would prevent the environment from being destroyed.
#
# The connector exists for the life of the workspace rather than only while the firewall is on.
# Azure refuses to delete a connector that a workspace still refers to, and the detach and the delete would otherwise be planned as one step, so turning the firewall off would fail and leave the environment half applied.
# It holds no role assignments while it is unattached.
resource "azurerm_databricks_access_connector" "root" {
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

# The resource group is passed as a plain name rather than looked up, so every argument is known at plan time and a tag change updates the workspace in place.
# The name, managed resource group, VNet, subnets, root storage account name and infrastructure encryption can be set only when the workspace is created; changing any of them replaces it.
resource "azurerm_databricks_workspace" "this" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  sku                               = "premium"
  managed_resource_group_name       = var.managed_resource_group_name
  public_network_access_enabled     = var.public_network_access_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  default_storage_firewall_enabled  = local.firewall_enabled
  access_connector_id               = local.access_connector_id
  tags                              = var.tags

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
}

# ----------------------------------------------------------------------------------------------------------------------
# State addresses
# ----------------------------------------------------------------------------------------------------------------------

# State that holds the connector at an indexed address is carried over to the unindexed one, so the existing connector is kept rather than replaced.
moved {
  from = azurerm_databricks_access_connector.root[0]
  to   = azurerm_databricks_access_connector.root
}
