provider "azurerm" {
  features {}

  tenant_id                       = var.tenant_id
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

provider "azapi" {
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"

  # Without this the provider falls back to azure_tenant_id = "common" and asks
  # the Azure CLI for a token against the common endpoint, which cannot be
  # issued silently. The apply then fails with:
  #   cannot get access token: Status_InteractionRequired
  #   ... azure_tenant_id=common
  # Pinning the real tenant makes the token request match the signed-in
  # context, consistent with the azurerm and azapi providers above.
  azure_tenant_id = var.tenant_id
}
