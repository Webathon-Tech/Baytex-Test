# ----------------------------------------------------------------------------------------------------------------------
# Databricks workspace module
# Creates the Premium Azure Databricks workspace with VNet injection, and the root Access Connector when the default storage firewall is enabled.
# ----------------------------------------------------------------------------------------------------------------------

locals {
  # The provider sets default_storage_firewall_enabled and access_connector_id together.
  # Both stay null while the firewall is off, which matches what Azure returns for a workspace without it, so plans show no change.
  firewall_enabled    = var.default_storage_firewall_enabled ? true : null
  access_connector_id = one(azurerm_databricks_access_connector.root[*].id)
}

# ----------------------------------------------------------------------------------------------------------------------
# Root Access Connector
# ----------------------------------------------------------------------------------------------------------------------

# Managed identity for the workspace root (DBFS) storage account, created only when default_storage_firewall_enabled is true.
# Once it is attached, Databricks exempts it from the managed resource group's deny assignment and grants its roles on the root storage account.
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
