locals {
  # The provider requires these two together and sends the connector only when the firewall is on. Both are null when
  # it is off, which keeps every plan clean.
  firewall_enabled    = var.default_storage_firewall_enabled ? true : null
  access_connector_id = var.default_storage_firewall_enabled ? azurerm_databricks_access_connector.root.id : null
}

# Identity for the workspace root (DBFS) storage account. It exists on every workspace so the storage firewall can be
# switched on without a code change, but it is attached only while default_storage_firewall_enabled is true. Databricks
# then exempts it from the managed resource group's deny assignment and grants its roles on the root storage account
# itself. Terraform grants nothing there: that deny assignment allows creating a role assignment but not deleting one,
# so a Terraform-owned assignment would make every destroy fail.
resource "azurerm_databricks_access_connector" "root" {
  name                = var.root_access_connector_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# resource_group_name is a plain string, never a data-source lookup, so the workspace's identity is known at plan time
# and a tag edit updates it in place instead of replacing it.
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
    no_public_ip                                         = true
    virtual_network_id                                   = var.virtual_network_id
    public_subnet_name                                   = var.host_subnet_name
    private_subnet_name                                  = var.container_subnet_name
    public_subnet_network_security_group_association_id  = var.host_nsg_association_id
    private_subnet_network_security_group_association_id = var.container_nsg_association_id
    storage_account_name                                 = var.root_storage_account_name
    storage_account_sku_name                             = "Standard_GRS"
  }
}
