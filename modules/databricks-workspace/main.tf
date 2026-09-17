# ----------------------------------------------------------------------------------------------------------------------
# Databricks workspace module
# Creates the Premium Azure Databricks workspace with VNet injection and secure cluster connectivity.
# ----------------------------------------------------------------------------------------------------------------------

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
